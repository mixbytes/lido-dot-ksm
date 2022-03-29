from brownie import chain
from helpers import RelayChain, distribute_initial_tokens


def test_redeem_right_after_deposit_equal(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")
    relay.new_ledger("0x20", "0x21")
    relay.new_ledger("0x30", "0x31")

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()

    assert relay.ledgers[0].free_balance > 0
    assert relay.ledgers[1].free_balance > 0
    assert relay.ledgers[2].free_balance > 0

    assert relay.ledgers[0].active_balance == 0
    assert relay.ledgers[1].active_balance == 0
    assert relay.ledgers[2].active_balance == 0

    for i in range(20):
        relay.new_era()

    # 0. Save ledger stakes before actions
    led1_stake = lido.ledgerStake(relay.ledgers[0].ledger_address)
    led2_stake = lido.ledgerStake(relay.ledgers[1].ledger_address)
    led3_stake = lido.ledgerStake(relay.ledgers[2].ledger_address)

    # 1. Deposit and redeem before new era
    deposit_2 = 5 * 10**18
    lido.deposit(deposit_2, {'from': accounts[1]})
    lido.redeem(deposit_2, {'from': accounts[1]})
    relay.new_era()

    # 2. Check token distirbution after new era
    led1_stake_upd = lido.ledgerStake(relay.ledgers[0].ledger_address)
    led2_stake_upd = lido.ledgerStake(relay.ledgers[1].ledger_address)
    led3_stake_upd = lido.ledgerStake(relay.ledgers[2].ledger_address)

    assert led1_stake_upd == led1_stake
    assert led2_stake_upd == led2_stake
    assert led3_stake_upd == led3_stake

    # 3. check unbonding balance
    (waitingToUnbonding, readyToClaim) = lido.getUnbonded(accounts[1])

    assert waitingToUnbonding == deposit_2
    assert readyToClaim == 0

    # 4. wait and check
    relay.new_era()

    (waitingToUnbonding, readyToClaim) = lido.getUnbonded(accounts[1])

    assert waitingToUnbonding == 0
    assert readyToClaim == deposit_2

    balance_before_claim = vKSM.balanceOf(accounts[1])
    lido.claimUnbonded({'from': accounts[1]})

    assert vKSM.balanceOf(accounts[1]) == (deposit_2 + balance_before_claim)


def test_redeem_right_after_deposit_less(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()
    relay.new_era()

    # 0. Save ledger stakes before actions
    led1_stake = lido.ledgerStake(relay.ledgers[0].ledger_address)

    # 1. Deposit and redeem before new era
    deposit_2 = 5 * 10**18
    redeem = 4 * 10**18
    lido.deposit(deposit_2, {'from': accounts[1]})
    lido.redeem(redeem, {'from': accounts[1]})
    relay.new_era()

    # 2. Check token distirbution after new era
    led1_stake_upd = lido.ledgerStake(relay.ledgers[0].ledger_address)

    assert led1_stake_upd == (led1_stake + (deposit_2 - redeem))

    # 3. check unbonding balance
    (waitingToUnbonding, readyToClaim) = lido.getUnbonded(accounts[1])

    assert waitingToUnbonding == redeem
    assert readyToClaim == 0

    # 4. wait and check
    relay.new_era()

    (waitingToUnbonding, readyToClaim) = lido.getUnbonded(accounts[1])

    assert waitingToUnbonding == 0
    assert readyToClaim == redeem

    balance_before_claim = vKSM.balanceOf(accounts[1])
    lido.claimUnbonded({'from': accounts[1]})

    assert vKSM.balanceOf(accounts[1]) == (redeem + balance_before_claim)


def test_redeem_right_after_deposit_greater(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()
    relay.new_era()

    # 0. Save ledger stakes before actions
    led1_stake = lido.ledgerStake(relay.ledgers[0].ledger_address)

    # 1. Deposit and redeem before new era
    deposit_2 = 5 * 10**18
    redeem = 8 * 10**18
    lido.deposit(deposit_2, {'from': accounts[0]})
    lido.redeem(redeem, {'from': accounts[0]})
    relay.new_era()

    # 2. Check token distirbution after new era
    led1_stake_upd = lido.ledgerStake(relay.ledgers[0].ledger_address)

    assert led1_stake_upd == (led1_stake - (redeem - deposit_2))

    # 3. check unbonding balance
    (waitingToUnbonding, readyToClaim) = lido.getUnbonded(accounts[0])

    assert waitingToUnbonding == redeem
    assert readyToClaim == 0

    # 5. wait for unbonding
    for i in range(33):
        relay.new_era()

    balance_before_claim = vKSM.balanceOf(accounts[0])
    lido.claimUnbonded({'from': accounts[0]})

    assert vKSM.balanceOf(accounts[0]) == (redeem + balance_before_claim)


def test_deposit_after_redeem_in_new_era(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")
    relay.new_ledger("0x20", "0x21")

    deposit = 20 * 10**12
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()
    relay.new_era()

    redeem = 10 * 10**12
    lido.redeem(redeem, {'from': accounts[0]})

    relay.new_era()

    assert relay.ledgers[0].active_balance == (deposit - redeem) / 2
    assert relay.ledgers[1].active_balance == (deposit - redeem) / 2

    lido.deposit(redeem, {'from': accounts[1]})

    relay.new_era() # transfer excess to withdrawal
    relay.new_era() # remove element from queue

    (waitingToUnbonding, readyToClaim) = lido.getUnbonded(accounts[0])

    assert waitingToUnbonding == 0
    assert readyToClaim == redeem

    balance_before_claim = vKSM.balanceOf(accounts[0])
    lido.claimUnbonded({'from': accounts[0]})

    assert vKSM.balanceOf(accounts[0]) == (redeem + balance_before_claim)


def test_deposit_after_redeem_in_new_era_less(lido, oracle_master, vKSM, Ledger, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")

    deposit = 20 * 10**12
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()
    relay.new_era()

    assert Ledger.at(lido.findLedger(relay.ledgers[0].stash_account)).ledgerStake() == deposit

    redeem = 5 * 10**12
    lido.redeem(redeem, {'from': accounts[0]})

    relay.new_era()

    assert Ledger.at(lido.findLedger(relay.ledgers[0].stash_account)).ledgerStake() == deposit - redeem

    deposit_2 = 15 * 10**12

    lido.deposit(deposit_2, {'from': accounts[1]})

    relay.new_era() # transfer excess to withdrawal
    relay.new_era() # remove element from queue

    assert Ledger.at(lido.findLedger(relay.ledgers[0].stash_account)).ledgerStake() == deposit + (deposit_2 - redeem)

    (waitingToUnbonding, readyToClaim) = lido.getUnbonded(accounts[0])

    assert waitingToUnbonding == 0
    assert readyToClaim == redeem

    balance_before_claim = vKSM.balanceOf(accounts[0])
    lido.claimUnbonded({'from': accounts[0]})

    assert vKSM.balanceOf(accounts[0]) == (redeem + balance_before_claim)


def test_deposit_after_redeem_in_new_era_greater(lido, oracle_master, vKSM, Ledger, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")

    deposit = 20 * 10**12
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()
    relay.new_era()

    assert Ledger.at(lido.findLedger(relay.ledgers[0].stash_account)).ledgerStake() == deposit

    redeem = 10 * 10**12
    lido.redeem(redeem, {'from': accounts[0]})

    relay.new_era()

    assert Ledger.at(lido.findLedger(relay.ledgers[0].stash_account)).ledgerStake() == deposit - redeem

    deposit_2 = 5 * 10**12

    lido.deposit(deposit_2, {'from': accounts[1]})

    relay.new_era()

    assert Ledger.at(lido.findLedger(relay.ledgers[0].stash_account)).ledgerStake() == deposit + (deposit_2 - redeem)

    (waitingToUnbonding, readyToClaim) = lido.getUnbonded(accounts[0])

    assert waitingToUnbonding == redeem
    assert readyToClaim == 0

    for i in range(32):
        relay.new_era()

    balance_before_claim = vKSM.balanceOf(accounts[0])
    lido.claimUnbonded({'from': accounts[0]})

    assert vKSM.balanceOf(accounts[0]) == (redeem + balance_before_claim)