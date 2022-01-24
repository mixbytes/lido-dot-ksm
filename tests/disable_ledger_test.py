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


def test_pause_ledger(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")
    relay.new_ledger("0x20", "0x21")

    ledger_1 = relay.ledgers[0]
    ledger_2 = relay.ledgers[1]

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()
    relay.new_era()

    assert ledger_1.active_balance == deposit // 2
    assert ledger_2.active_balance == deposit // 2

    lido.emergencyPauseLedger(ledger_2.ledger_address, {'from': accounts[0]})
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()
    relay.new_era()

    assert ledger_1.active_balance == 3 * deposit // 2
    assert ledger_2.active_balance == deposit // 2

    lido.redeem(deposit, {'from': accounts[0]})

    relay.new_era()

    assert ledger_1.active_balance == deposit // 2
    assert ledger_2.active_balance == deposit // 2

    lido.resumeLedger(ledger_2.ledger_address, {'from': accounts[0]})

    lido.redeem(deposit // 2, {'from': accounts[0]})

    relay.new_era()

    assert ledger_1.active_balance == deposit // 2
    assert ledger_2.active_balance == 0