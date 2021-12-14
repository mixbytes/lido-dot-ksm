from brownie import chain
from helpers import RelayChain, distribute_initial_tokens


def test_disable_ledger(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")
    relay.new_ledger("0x20", "0x21")

    ledger_1 = relay.ledgers[0]
    ledger_2 = relay.ledgers[1]

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()

    assert ledger_1.free_balance == deposit // 2
    assert ledger_2.free_balance == deposit // 2

    relay.new_era()

    assert ledger_1.active_balance == deposit // 2
    assert ledger_2.active_balance == deposit // 2

    lido.disableLedger(ledger_2.ledger_address, {'from': accounts[0]})
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()

    assert ledger_1.active_balance == deposit // 2
    assert ledger_1.free_balance == deposit

    assert ledger_2.active_balance == deposit // 2
    assert ledger_2.free_balance == 0


def test_move_funds_from_disable_ledger(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")
    relay.new_ledger("0x20", "0x21")

    ledger_1 = relay.ledgers[0]
    ledger_2 = relay.ledgers[1]

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()

    lido.disableLedger(ledger_2.ledger_address, {'from': accounts[0]})
    
    relay.new_era()

    lido.moveDisabledLedgersStake([ledger_2.ledger_address], {'from': accounts[0]})

    relay.new_era()

    assert ledger_1.active_balance == deposit // 2
    assert ledger_2.active_balance == 0

    for i in range(28):
        relay.new_era()
        assert ledger_2.free_balance == 0

    relay.new_era()
    assert ledger_2.free_balance == deposit // 2

    relay.new_era()
    relay.new_era()

    assert vKSM.balanceOf(lido) == deposit // 2
    assert ledger_2.free_balance == 0

    relay.new_era()

    assert ledger_1.active_balance == deposit // 2
    assert ledger_1.free_balance == deposit // 2


def test_redeem_after_move(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")
    relay.new_ledger("0x20", "0x21")

    ledger_1 = relay.ledgers[0]
    ledger_2 = relay.ledgers[1]

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()

    lido.disableLedger(ledger_2.ledger_address, {'from': accounts[0]})
    
    relay.new_era()

    lido.moveDisabledLedgersStake([ledger_2.ledger_address], {'from': accounts[0]})

    lido.redeem(deposit // 4, {'from': accounts[0]})

    relay.new_era()

    assert ledger_1.active_balance == deposit // 2
    assert ledger_2.active_balance == 0

    for i in range(28):
        relay.new_era()
        assert ledger_1.active_balance == deposit // 2
        assert ledger_2.free_balance == 0

    relay.new_era()
    assert ledger_2.free_balance == deposit // 2

    relay.new_era()
    relay.new_era()

    assert vKSM.balanceOf(lido) == deposit // 2
    assert ledger_2.free_balance == 0

    balance_before = vKSM.balanceOf(accounts[0])
    lido.claimUnbonded({'from': accounts[0]})
    balance_after = vKSM.balanceOf(accounts[0])

    relay.new_era()

    assert ledger_1.active_balance == deposit // 2
    assert ledger_1.free_balance == deposit // 4
    assert balance_after - balance_before == deposit // 4


def test_slash_after_move(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")
    relay.new_ledger("0x20", "0x21")

    ledger_1 = relay.ledgers[0]
    ledger_2 = relay.ledgers[1]

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()

    lido.disableLedger(ledger_2.ledger_address, {'from': accounts[0]})
    
    relay.new_era()

    lido.moveDisabledLedgersStake([ledger_2.ledger_address], {'from': accounts[0]})

    ledger2_loss = 1 * 10**18
    relay.new_era([0, -ledger2_loss])

    assert ledger_1.active_balance == deposit // 2
    assert ledger_2.active_balance == 0

    for i in range(28):
        relay.new_era()
        assert ledger_2.free_balance == 0

    relay.new_era()
    assert ledger_2.free_balance == deposit // 2 - ledger2_loss

    relay.new_era()
    relay.new_era()

    assert vKSM.balanceOf(lido) == deposit // 2 - ledger2_loss
    assert ledger_2.free_balance == 0

    relay.new_era()

    assert ledger_1.active_balance == deposit // 2
    assert ledger_1.free_balance == deposit // 2 - ledger2_loss


def test_redeem_before_move(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")
    relay.new_ledger("0x20", "0x21")

    ledger_1 = relay.ledgers[0]
    ledger_2 = relay.ledgers[1]

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()

    lido.disableLedger(ledger_2.ledger_address, {'from': accounts[0]})
    
    relay.new_era()

    lido.redeem(deposit // 4, {'from': accounts[0]})

    lido.moveDisabledLedgersStake([ledger_2.ledger_address], {'from': accounts[0]})

    relay.new_era()

    assert ledger_1.active_balance == deposit // 2
    assert ledger_2.active_balance == 0

    for i in range(28):
        relay.new_era()
        assert ledger_1.active_balance == deposit // 2
        assert ledger_2.free_balance == 0

    relay.new_era()
    assert ledger_2.free_balance == deposit // 2

    relay.new_era()
    relay.new_era()

    assert vKSM.balanceOf(lido) == deposit // 2
    assert ledger_2.free_balance == 0

    balance_before = vKSM.balanceOf(accounts[0])
    lido.claimUnbonded({'from': accounts[0]})
    balance_after = vKSM.balanceOf(accounts[0])

    relay.new_era()

    assert ledger_1.active_balance == deposit // 2
    assert ledger_1.free_balance == deposit // 4
    assert balance_after - balance_before == deposit // 4