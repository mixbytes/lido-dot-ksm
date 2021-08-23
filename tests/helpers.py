class RelayLegder:
    ledger_address = None
    stash_account = None
    controller_account = None

    active_balance = 0
    free_balance = 0
    unlocking_chunks = []
    validators = 0
    status = None

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
        self.status = None

    def unbond(self, amount):
        assert self.active_balance >= amount
        self.active_balance -= amount
        self.unlocking_chunks.append((amount, self.relay.era + 28))
        assert len(self.unlocking_chunks) < 32

    def bond(self, amount):
        assert self.free_balance >= amount
        self.active_balance += amount
        self.free_balance -= amount

    def bond_extra(self, amount):
        assert self.free_balance >= amount
        self.active_balance += amount
        self.free_balance -= amount

    def rebond(self, amount):
        rebonded = 0
        while len(self.unlocking_chunks) > 0 and rebonded < amount:
            rebonded += self.unlocking_chunks[0][0]
            self.unlocking_chunks.pop(0)

    def withdraw(self):
        while len(self.unlocking_chunks) > 0 and self.unlocking_chunks[0][1] < self.relay.era:
            self.free_balance += self.unlocking_chunks[0][0]
            self.unlocking_chunks.pop(0)

    def _unlocking_sum(self):
        sum = 0
        for i in range(len(self.unlocking_chunks)):
            sum += self.unlocking_chunks[i][0]
        return sum

    def _status_num(self):
        if self.status == 'Chill':
            return 0
        elif self.status == 'Nominator':
            return 1
        elif self.status == 'Validator':
            return 2
        else:
            return 3
    
    def get_report_data(self):
        return (
            self.stash_account, 
            self.controller_account,
            self._status_num(),
            self.active_balance, 
            self.active_balance + self._unlocking_sum(), 
            self.unlocking_chunks, 
            [], 
            self.active_balance + self._unlocking_sum() + self.free_balance
        )


class RelayChain:
    lido = None
    vKSM = None
    oracle_master = None
    accounts = None
    ledgers = []
    era = 2
    total_rewards = 0

    def __init__(self, lido, vKSM, oracle_master, accounts):
        self.lido = lido
        self.vKSM = vKSM
        self.oracle_master = oracle_master
        self.accounts = accounts

        self.oracle_master.addOracleMember(self.accounts[0], {'from': self.accounts[0]})
        self.oracle_master.setQuorum(1, {'from': self.accounts[0]})

        self.ledgers = []
        self.era = 2
        self.total_rewards = 0

    def new_ledger(self, stash_account, controller_account, share):
        tx = self.lido.addLedger(stash_account, controller_account, share, {'from': self.accounts[0]})
        tx.info()
        self.ledgers.append(RelayLegder(self, tx.events['LegderAdded'][0]['addr'], stash_account, controller_account))

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

    def _process_downward_transfer(self, event):
        idx = self._ledger_idx_by_stash_account(event['from'])
        assert self.ledgers[idx].free_balance >= event['amount']
        self.ledgers[idx].free_balance -= event['amount']
        self.vKSM.mint(event['to'], event['amount'], {'from': self.accounts[0]}).info()

    def _process_call(self, name, event):
        if name == 'Bond':
            idx = self._ledger_idx_by_ledger_address(event['caller'])
            self.ledgers[idx].bond(event['amount'])
        elif name == 'BondExtra':
            idx = self._ledger_idx_by_ledger_address(event['caller'])
            self.ledgers[idx].bond_extra(event['amount'])
        elif name == 'Unbond':
            idx = self._ledger_idx_by_ledger_address(event['caller'])
            self.ledgers[idx].unbond(event['amount'])
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
        for i in range(len(tx.events)):
            name = tx.events[i].name
            event = tx.events[i]
            if name == 'UpwardTransfer':
                self._process_upward_transfer(event)
            elif name == 'DownwardTransfer':
                self._process_downward_transfer(event)
            else:
                self._process_call(name, event)

    def new_era(self, rewards = []):
        self.era += 1
        for i in range(len(self.ledgers)):
            if i < len(rewards) and self.ledgers[i].status != 'Chill':
                self.ledgers[i].active_balance += rewards[i]
                self.total_rewards += rewards[i]
            tx = self.oracle_master.reportRelay(self.era, self.ledgers[i].get_report_data())
            tx.info()
            self._after_report(tx)

    def timetravel(self, eras):
        self.era += eras



def distribute_initial_tokens(vKSM, lido, accounts):
    for acc in accounts[1:]:
        vKSM.transfer(acc, 10**6 * 10**18, {'from': accounts[0]})

    for acc in accounts:
        vKSM.approve(lido, 2**255, {'from': acc})