from brownie import chain
from helpers import RelayChain, distribute_initial_tokens


def test_add_multi_ledgers(lido, oracle_master, vKSM, Ledger, accounts):
    for stash in (0x10, 0x20, 0x30):
        lido.addLedger(hex(stash), hex(stash + 1), 100, {'from': accounts[0]})
        ledger = Ledger.at(lido.findLedger(hex(stash)))
        assert ledger.stashAccount() == hex(stash)


def test_deposit_distribution(lido, oracle_master, vKSM, Ledger, accounts):
    stashes = [0x10, 0x20, 0x30]
    shares = [100, 50, 10]
    total_shares = sum(i for i in shares)
    total_deposit = 0

    def check_distribution():
        stakes_sum = 0
        for i in range(len(stashes)):
            stash = hex(stashes[i])
            ledger = Ledger.at(lido.findLedger(stash))
            stakes_sum += ledger.ledgerStake()
            assert abs(ledger.ledgerStake() - total_deposit * shares[i] // total_shares) < total_shares
        assert stakes_sum == total_deposit

    for i in range(len(stashes)):
        stash = stashes[i]
        lido.addLedger(hex(stash), hex(stash + 1), shares[i], {'from': accounts[0]})

    distribute_initial_tokens(vKSM, lido, accounts)

    # first deposit
    deposit = 1000 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[0]})
    lido.flushStakes({'from': oracle_master})
    check_distribution()

    # one another deposit
    deposit = 9905 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[1]})
    lido.flushStakes({'from': oracle_master})
    check_distribution()


def test_change_shares_distribution(lido, oracle_master, vKSM, Ledger, accounts):
    stashes = [0x10, 0x20, 0x30]
    shares = [100, 50, 10]
    total_shares = sum(i for i in shares)
    total_deposit = 0

    def check_distribution():
        stakes_sum = 0
        for i in range(len(stashes)):
            stash = hex(stashes[i])
            ledger = Ledger.at(lido.findLedger(stash))
            stakes_sum += ledger.ledgerStake()
            assert abs(ledger.ledgerStake() - total_deposit * shares[i] // total_shares) < total_shares
        assert stakes_sum == total_deposit

    for i in range(len(stashes)):
        stash = stashes[i]
        lido.addLedger(hex(stash), hex(stash + 1), shares[i], {'from': accounts[0]})

    distribute_initial_tokens(vKSM, lido, accounts)

    # first deposit
    deposit = 1000 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[0]})
    lido.flushStakes({'from': oracle_master})
    check_distribution()

    # change ledgers shares
    shares = [10, 500, 100]
    total_shares = sum(i for i in shares)
    for i in range(len(stashes)):
        stash = stashes[i]
        lido.setLedgerShare(lido.findLedger(hex(stashes[i])), shares[i])

    deposit = 1000000 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[0]})
    lido.flushStakes({'from': oracle_master})
    check_distribution()


def test_redeem_distribution(lido, oracle_master, vKSM, Ledger, accounts):
    stashes = [0x10, 0x20, 0x30]
    shares = [100, 50, 10]
    total_shares = sum(i for i in shares)
    total_deposit = 0

    def check_distribution():
        stakes_sum = 0
        for i in range(len(stashes)):
            stash = hex(stashes[i])
            ledger = Ledger.at(lido.findLedger(stash))
            stakes_sum += ledger.ledgerStake()
            assert abs(ledger.ledgerStake() - total_deposit * shares[i] // total_shares) < total_shares
        assert stakes_sum == total_deposit

    for i in range(len(stashes)):
        stash = stashes[i]
        lido.addLedger(hex(stash), hex(stash + 1), shares[i], {'from': accounts[0]})

    distribute_initial_tokens(vKSM, lido, accounts)

    # first deposit
    deposit = 1000 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[0]})
    lido.flushStakes({'from': oracle_master})
    check_distribution()

    total_deposit -= deposit // 2
    lido.redeem(deposit // 2, {'from': accounts[0]})
    lido.flushStakes({'from': oracle_master})
    check_distribution()


def test_huge_amount_ledgers(lido, oracle_master, vKSM, Ledger, accounts):
    LEDGER_AMOUNT = 60
    stashes = [i for i in range(LEDGER_AMOUNT)]
    shares = [100] * LEDGER_AMOUNT
    total_shares = sum(i for i in shares)
    total_deposit = 0

    def check_distribution():
        stakes_sum = 0
        for i in range(len(stashes)):
            stash = hex(stashes[i])
            ledger = Ledger.at(lido.findLedger(stash))
            stakes_sum += ledger.ledgerStake()
            assert abs(ledger.ledgerStake() - total_deposit * shares[i] // total_shares) < total_shares
        assert stakes_sum == total_deposit

    for i in range(len(stashes)):
        stash = stashes[i]
        lido.addLedger(hex(stash), hex(stash + 1), shares[i], {'from': accounts[0]})

    distribute_initial_tokens(vKSM, lido, accounts)

    # first deposit
    deposit = 1000 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[0]})
    tx = lido.flushStakes({'from': oracle_master})
    print('GAS USED:', tx.gas_used)
    check_distribution()


def test_available_for_stake(lido, oracle_master, vKSM, Ledger, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)
    stashes = [0x10, 0x20]
    shares = [100, 100]
    total_deposit = 0

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger(hex(stashes[0]), hex(stashes[0]+1), shares[0])
    relay.new_ledger(hex(stashes[1]), hex(stashes[1]+1), shares[1])

    deposit = 1000 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[0]})

    rewards = 200 * 10**18
    relay.new_era([rewards * 2, rewards])  # upward transfer
    relay.new_era([rewards * 2, rewards])  # bond

    deposit = 100 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[0]})

    redeem = 200 * 10**18
    total_deposit -= redeem
    lido.redeem(redeem, {'from': accounts[0]})

    relay.new_era()  # execute rebalance & up/down transfers
    relay.new_era()  # complete bonding/unbonding

    # ledegers shouldn't bond
    expected_total_ledgers_balance = 1000 * 10**18 + rewards * 6
    assert(relay.ledgers[0].total_balance() + relay.ledgers[1].total_balance() == expected_total_ledgers_balance)
