from brownie import Ledger


BONDING_DURATION = 28  # Polkadot
MAX_UNLOCKING_CHUNKS = 32  # defined in the staking pallet

MINIMUM_BALANCE = 33_333_333  # Existential Deposit in Kusama
# MINIMUM_BALANCE = 10_000_000_000  # Existential Deposit in Polkadot

MIN_NOMINATOR_BOND = 100_000_000_000  # Kusama and Polkadot
MIN_VALIDATOR_BOND = 0  # Kusama and Polkadot


class RelayLedger:
    ledger_address = None
    stash_account = None
    controller_account = None

    active_balance: int
    free_balance: int
    unlocking_chunks: list
    validators: int
    status: str

    bonded: bool
    relay = None

    def __init__(self, relay, ledger_address, stash_account, controller_account):
        self.relay = relay
        self.ledger_address = ledger_address
        self.stash_account = stash_account
        self.controller_account = controller_account

        self.active_balance = 0
        self.free_balance = 0
        self.unlocking_chunks = []
        self.validators = 0
        self.status = ''

        self.bonded = False

    def total_balance(self) -> int:
        return self.active_balance + self._unlocking_sum() + self.free_balance

    # https://github.com/paritytech/substrate/blob/814752f60ab8cce7e2ece3ce0c1b10799b4eab28/frame/staking/src/pallet/mod.rs#L871-L952
    def unbond(self, amount: int, era: int):
        if amount == 0:
            return

        assert self.active_balance >= amount
        assert len(self.unlocking_chunks) < MAX_UNLOCKING_CHUNKS, "No more chunks"
        if amount == 0:
            return

        # https://github.com/paritytech/substrate/blob/814752f60ab8cce7e2ece3ce0c1b10799b4eab28/frame/staking/src/pallet/mod.rs#L905-L923
        self.active_balance -= amount
        if self.active_balance < MINIMUM_BALANCE:
            amount += self.active_balance
            self.active_balance = 0

        if self.status == 'Validator':
            assert self.active_balance >= MIN_VALIDATOR_BOND, "Insufficient bond"
        elif self.status == 'Nominator':
            assert self.active_balance >= MIN_NOMINATOR_BOND, "Insufficient bond"

        # https://github.com/paritytech/substrate/blob/814752f60ab8cce7e2ece3ce0c1b10799b4eab28/frame/staking/src/pallet/mod.rs#L925-L939
        found_chunk = False
        for c in self.unlocking_chunks:
            if c[1] == era:
                c[0] += amount
                found_chunk = True
                break
        if not found_chunk:
            self.unlocking_chunks.append([amount, self.relay.era + BONDING_DURATION])

        self.bonded = False

    # https://github.com/paritytech/substrate/blob/814752f60ab8cce7e2ece3ce0c1b10799b4eab28/frame/staking/src/pallet/mod.rs#L755-L819
    def bond(self, amount: int):
        assert not self.bonded, "Already bonded"
        assert self.free_balance >= amount
        assert amount >= MINIMUM_BALANCE, "Insufficient bond"

        self.active_balance += amount
        self.free_balance -= amount
        self.bonded = True

    # https://github.com/paritytech/substrate/blob/814752f60ab8cce7e2ece3ce0c1b10799b4eab28/frame/staking/src/pallet/mod.rs#L821-L869
    def bond_extra(self, amount: int):
        assert self.bonded, "Not bonded"
        assert self.free_balance >= amount

        extra = self.free_balance - (self.active_balance + self._unlocking_sum())
        amount = min(amount, extra) if extra >= 0 else amount

        self.active_balance += amount
        self.free_balance -= amount
        assert self.active_balance >= MINIMUM_BALANCE, "Insufficient bond"

    # https://github.com/paritytech/substrate/blob/814752f60ab8cce7e2ece3ce0c1b10799b4eab28/frame/staking/src/pallet/mod.rs#L1403-L1439
    def rebond(self, amount: int):
        assert len(self.unlocking_chunks) != 0, "No unlock chunk"

        # https://github.com/paritytech/substrate/blob/814752f60ab8cce7e2ece3ce0c1b10799b4eab28/frame/staking/src/lib.rs#L509-L527
        rebonded_value = 0
        while self.unlocking_chunks:
            chunk = self.unlocking_chunks[-1]
            if rebonded_value + chunk[0] <= amount:
                rebonded_value += chunk[0]
                self.unlocking_chunks.pop()
            else:
                diff = amount - rebonded_value
                rebonded_value += diff
                chunk[0] -= diff
                break

            if rebonded_value >= amount:
                break

        self.active_balance += rebonded_value
        # https://github.com/paritytech/substrate/blob/814752f60ab8cce7e2ece3ce0c1b10799b4eab28/frame/staking/src/pallet/mod.rs#L1424
        assert self.active_balance >= MINIMUM_BALANCE, "Insufficient bond"
        self.bonded = True

    # https://github.com/paritytech/substrate/blob/814752f60ab8cce7e2ece3ce0c1b10799b4eab28/frame/staking/src/pallet/mod.rs#L954-L1009
    # https://github.com/paritytech/substrate/blob/814752f60ab8cce7e2ece3ce0c1b10799b4eab28/frame/staking/src/lib.rs#L475-L503
    def withdraw(self):
        while self.unlocking_chunks and self.unlocking_chunks[0][1] < self.relay.era:
            self.free_balance += self.unlocking_chunks[0][0]
            self.unlocking_chunks.pop(0)

    def _unlocking_sum(self) -> int:
        return sum(i[0] for i in self.unlocking_chunks)

    def _status_num(self) -> int:
        if self.status == 'Chill':
            return 0
        elif self.status == 'Nominator':
            return 1
        elif self.status == 'Validator':
            return 2
        else:
            return 3

    def get_report_data(self) -> tuple:
        return (
            self.stash_account,
            self.controller_account,
            self._status_num(),
            self.active_balance,
            self.active_balance + self._unlocking_sum(),
            self.unlocking_chunks,
            [],
            self.total_balance(),
            0  # ledger slashing spans (for test always 0)
        )


class RelayChain:
    lido = None
    vKSM = None
    oracle_master = None
    accounts = None
    ledgers = []
    era = 0
    total_rewards = 0
    chain = None
    bond_enabled = True
    transfer_enabled = True
    block_xcm_messages = False

    def __init__(self, lido, vksm, oracle_master, accounts, chain):
        self.lido = lido
        self.vKSM = vksm
        self.oracle_master = oracle_master
        self.accounts = accounts
        self.chain = chain

        self.oracle_master.addOracleMember(self.accounts[0], {'from': self.accounts[0]})
        self.oracle_master.setQuorum(1, {'from': self.accounts[0]})

        self.ledgers = []
        self.era = 0
        self.total_rewards = 0

    def new_ledger(self, stash_account, controller_account):
        tx = self.lido.addLedger(stash_account, controller_account, 0, {'from': self.accounts[0]})
        tx.info()
        self.ledgers.append(RelayLedger(self, tx.events['LedgerAdd'][0]['addr'], stash_account, controller_account))
        Ledger.at(tx.events['LedgerAdd'][0]['addr']).refreshAllowances({'from': self.accounts[0]})

    def disable_bond(self):
        self.bond_enabled = False

    def enable_bond(self):
        self.bond_enabled = True

    def disable_transfer(self):
        self.transfer_enabled = False

    def enable_transfer(self):
        self.transfer_enabled = True

    def _ledger_idx_by_stash_account(self, stash_account):
        for i in range(len(self.ledgers)):
            if self.ledgers[i].stash_account == stash_account:
                return i
        assert False, "not found ledger"

    def _ledger_idx_by_controller_account(self, stash_account):
        for i in range(len(self.ledgers)):
            if self.ledgers[i].stash_account == stash_account:
                return i
        assert False, "not found ledger"

    def _ledger_idx_by_ledger_address(self, ledger_address):
        for i in range(len(self.ledgers)):
            if self.ledgers[i].ledger_address == ledger_address:
                return i
        assert False, "not found ledger"

    def _process_upward_transfer(self, event):
        idx = self._ledger_idx_by_stash_account(event['to'])
        self.ledgers[idx].free_balance += event['amount']
        self.vKSM.burn(event['from'], event['amount'], {'from': self.accounts[0]}).info()

    def _process_downward_transfer(self, event):
        idx = self._ledger_idx_by_stash_account(event['from'])
        assert self.ledgers[idx].free_balance >= event['amount']
        self.ledgers[idx].free_balance -= event['amount']
        self.vKSM.mint(event['to'], event['amount'], {'from': self.accounts[0]}).info()

    def _process_call(self, name, event):
        if name == 'Bond':
            if self.bond_enabled:
                idx = self._ledger_idx_by_ledger_address(event['caller'])
                self.ledgers[idx].bond(event['amount'])
        elif name == 'BondExtra':
            idx = self._ledger_idx_by_ledger_address(event['caller'])
            self.ledgers[idx].bond_extra(event['amount'])
        elif name == 'Unbond':
            idx = self._ledger_idx_by_ledger_address(event['caller'])
            self.ledgers[idx].unbond(event['amount'], self.era + BONDING_DURATION)
        elif name == 'Rebond':
            idx = self._ledger_idx_by_ledger_address(event['caller'])
            self.ledgers[idx].rebond(event['amount'])
        elif name == 'Withdraw':
            idx = self._ledger_idx_by_ledger_address(event['caller'])
            self.ledgers[idx].withdraw()
        elif name == 'Nominate':
            idx = self._ledger_idx_by_ledger_address(event['caller'])
            self.ledgers[idx].validators += event['validators']
            self.ledgers[idx].status = 'Nominator'
        elif name == 'Chill':
            idx = self._ledger_idx_by_ledger_address(event['caller'])
            self.ledgers[idx].status = 'Chill'
            pass

    def _after_report(self, tx):
        if not self.block_xcm_messages:
            for i in range(len(tx.events)):
                name = tx.events[i].name
                event = tx.events[i]
                if name == 'TransferToRelaychain':
                    if self.transfer_enabled:
                        self._process_upward_transfer(event)
                elif name == 'TransferToParachain':
                    self._process_downward_transfer(event)
                else:
                    self._process_call(name, event)

    # https://github.com/paritytech/substrate/blob/814752f60ab8cce7e2ece3ce0c1b10799b4eab28/frame/staking/src/lib.rs#L587-L602
    @staticmethod
    def _slash_out_of(target: int, remaining_slash: int,
                      affected_balance: int, slash_amount: int, ratio: float) -> (int, int):
        if slash_amount < affected_balance:
            slash_from_target = ratio * target
        else:
            slash_from_target = remaining_slash
            
        slash_from_target = target if slash_from_target < target else slash_from_target
        target -= slash_from_target
        if target < MINIMUM_BALANCE:
            slash_from_target += target
            target = 0
            
        remaining_slash -= slash_from_target
        
        return target, remaining_slash

    # https://github.com/paritytech/substrate/blob/814752f60ab8cce7e2ece3ce0c1b10799b4eab28/frame/staking/src/lib.rs#L532-L624
    def slash(self, rewards: list, i: int):
        slash_amount = rewards[i]
        remaining_slash = rewards[i]

        era_after_slash = self.era + 1
        chunk_unlock_era_after_slash = era_after_slash + BONDING_DURATION

        # https://github.com/paritytech/substrate/blob/814752f60ab8cce7e2ece3ce0c1b10799b4eab28/frame/staking/src/lib.rs#L561-L583
        affected_balance, slash_chunks_priority = None, None
        for idx, unlocking in enumerate(self.ledgers[i].unlocking_chunks):
            era = unlocking[1]
            if era < chunk_unlock_era_after_slash:
                continue
            
            affected_indices = [j for j in range(idx, len(self.ledgers[i].unlocking_chunks))]
            affected_balance = self.ledgers[i].active_balance
            for _idx in affected_indices:
                affected_balance += self.ledgers[i].unlocking_chunks[_idx]
                slash_chunks_priority = [j for j in range(idx)].reverse()
            break
        if affected_balance is None:
            affected_balance = self.ledgers[i].active_balance
            slash_chunks_priority = [j for j in range(len(self.ledgers[i].unlocking_chunks))]

        # https://github.com/paritytech/substrate/blob/814752f60ab8cce7e2ece3ce0c1b10799b4eab28/frame/staking/src/lib.rs#L586
        ratio = slash_amount / affected_balance

        # https://github.com/paritytech/substrate/blob/814752f60ab8cce7e2ece3ce0c1b10799b4eab28/frame/staking/src/lib.rs#L605
        self.ledgers[i].active_balance, remaining_slash = self._slash_out_of(
            affected_balance=affected_balance,
            ratio=ratio,
            remaining_slash=remaining_slash,
            slash_amount=slash_amount,
            target=self.ledgers[i].active_balance,
        )
        
        # https://github.com/paritytech/substrate/blob/814752f60ab8cce7e2ece3ce0c1b10799b4eab28/frame/staking/src/lib.rs#L608-L621
        for c in slash_chunks_priority:
            if not self.ledgers[i].unlocking_chunks:
                break
                
            if remaining_slash == 0:
                break

            self.ledgers[i].unlocking_chunks[c][0], remaining_slash = self._slash_out_of(
                affected_balance=affected_balance,
                ratio=ratio,
                remaining_slash=remaining_slash,
                slash_amount=slash_amount,
                target=self.ledgers[i].unlocking_chunks[c][0],
            )

        unlocking_upd = []
        for c in self.ledgers[i].unlocking_chunks:
            if c[0] != 0:
                unlocking_upd.append(c)
        self.ledgers[i].unlocking_chunks = unlocking_upd
        rewards[i] = 0

    def new_era(self, rewards: list = None):
        if rewards is None:
            rewards = []

        self.era += 1
        self.chain.sleep(6 * 60 * 60)
        for i in range(len(self.ledgers)):
            if i < len(rewards) and self.ledgers[i].status != 'Chill':
                self.total_rewards += rewards[i]
                if rewards[i] >= 0:
                    self.ledgers[i].active_balance += rewards[i]
                else:
                    self.slash(rewards, i)
                    assert rewards[i] == 0

            tx = self.oracle_master.reportRelay(self.era, self.ledgers[i].get_report_data())
            tx.info()
            self._after_report(tx)

    def timetravel(self, eras):
        self.chain.sleep(6 * 60 * 60 * eras)
        self.era += eras
        self.chain.mine()


def distribute_initial_tokens(vksm, lido, accounts):
    for acc in accounts[1:]:
        vksm.transfer(acc, 10 ** 6 * 10 ** 18, {'from': accounts[0]})

    for acc in accounts:
        vksm.approve(lido, 2 ** 255, {'from': acc})
