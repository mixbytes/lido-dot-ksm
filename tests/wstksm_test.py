from brownie import chain
from helpers import RelayChain, distribute_initial_tokens


def test_wrap_stksm(lido, oracle_master, vKSM, accounts, wstKSM):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")

    ledger_1 = relay.ledgers[0]

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()

    lido.approve(wstKSM, deposit // 2, {'from': accounts[0]})
    wstKSM.wrap(deposit // 2, {'from': accounts[0]})

    assert lido.balanceOf(accounts[0]) == deposit // 2
    assert lido.balanceOf(wstKSM) == deposit // 2
    assert wstKSM.balanceOf(accounts[0]) == deposit // 2

    wstKSM.unwrap(deposit // 2, {'from': accounts[0]})

    assert lido.balanceOf(accounts[0]) == deposit
    assert lido.balanceOf(wstKSM) == 0
    assert wstKSM.balanceOf(accounts[0]) == 0


def test_wrap_after_rewards(lido, oracle_master, vKSM, accounts, wstKSM):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")

    ledger_1 = relay.ledgers[0]

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()

    reward = 2 * 10**18
    relay.new_era([reward])

    lido.approve(wstKSM, deposit // 2, {'from': accounts[0]})
    wstKSM.wrap(deposit // 2, {'from': accounts[0]})

    assert wstKSM.balanceOf(accounts[0]) == lido.sharesOf(wstKSM)

    wstKSM.unwrap(wstKSM.balanceOf(accounts[0]), {'from': accounts[0]})

    assert wstKSM.balanceOf(accounts[0]) == 0


def test_wrap_after_slashing(lido, oracle_master, vKSM, accounts, wstKSM):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")

    ledger_1 = relay.ledgers[0]

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()
    relay.new_era()

    loss = -2 * 10**18
    relay.new_era([loss])

    lido.approve(wstKSM, deposit // 2, {'from': accounts[0]})
    wstKSM.wrap(deposit // 2, {'from': accounts[0]})

    assert wstKSM.balanceOf(accounts[0]) == lido.sharesOf(wstKSM)

    wstKSM.unwrap(wstKSM.balanceOf(accounts[0]), {'from': accounts[0]})

    assert wstKSM.balanceOf(accounts[0]) == 0