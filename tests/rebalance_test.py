from brownie import chain
from helpers import RelayChain, distribute_initial_tokens

def test_equal_deposit_bond(lido, Ledger, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")
    relay.new_ledger("0x20", "0x21")

    ledger_1 = relay.ledgers[0]
    ledger_2 = relay.ledgers[1]

    deposit_1 = 100 * 10**18
    lido.deposit(deposit_1, {'from': accounts[0]})

    relay.new_era()

    assert ledger_1.free_balance == deposit_1 // 2
    assert ledger_1.active_balance == 0

    assert ledger_2.free_balance == deposit_1 // 2
    assert ledger_2.active_balance == 0

    ledgerContract_1 = Ledger.at(ledger_1.ledger_address)
    ledgerContract_2 = Ledger.at(ledger_2.ledger_address)

    for i in range(3):
        deposit_i = (i + 1) * 10 * 10**18
        lido.deposit(deposit_i, {'from': accounts[0]})

        reward = 2 * 10**18
        relay.new_era([reward])

        assert ledger_1.total_balance() == lido.ledgerBorrow(ledger_1.ledger_address)
        assert ledger_2.total_balance() == lido.ledgerBorrow(ledger_2.ledger_address)

    for i in range(3):
        redeem_i = (i + 1) * 10 * 10**18
        lido.redeem(redeem_i, {'from': accounts[0]})

        reward = 2 * 10**18
        relay.new_era([reward])

        assert ledger_1.total_balance() + ledgerContract_1.transferUpwardBalance() + ledgerContract_1.transferDownwardBalance() == lido.ledgerBorrow(ledger_1.ledger_address)
        assert ledger_2.total_balance() + ledgerContract_2.transferUpwardBalance() + ledgerContract_2.transferDownwardBalance() == lido.ledgerBorrow(ledger_2.ledger_address)


def test_direct_transfer(lido, Ledger, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")
    ledger_1 = relay.ledgers[0]

    deposit = 100 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()
    relay.new_era()

    # first redeem
    redeem = 50 * 10**18
    lido.redeem(redeem, {'from': accounts[0]})

    for i in range(31):
        relay.new_era()

    assert lido.ledgerBorrow(ledger_1.ledger_address) == deposit

    direct_transfer = 10 * 10**18
    vKSM.transfer(ledger_1.ledger_address, direct_transfer, {'from': accounts[1]})

    relay.new_era()
    assert lido.ledgerBorrow(ledger_1.ledger_address) == deposit - redeem - direct_transfer

    # second redeem
    lido.redeem(redeem, {'from': accounts[0]})

    for i in range(32):
        relay.new_era()

    assert lido.getTotalPooledKSM() == direct_transfer