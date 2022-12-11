from brownie import chain
from helpers import RelayChain, distribute_initial_tokens


def test_wrap_stksm(lido, oracle_master, vKSM, accounts, xcWSTDOT, localAsset):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()

    lido.approve(xcWSTDOT, deposit // 2, {'from': accounts[0]})
    xcWSTDOT.wrap(deposit // 2, {'from': accounts[0]})

    assert lido.balanceOf(accounts[0]) == deposit // 2
    assert lido.balanceOf(xcWSTDOT) == deposit // 2
    assert localAsset.balanceOf(accounts[0]) == deposit // 2

    xcWSTDOT.unwrap(deposit // 2, {'from': accounts[0]})

    assert lido.balanceOf(accounts[0]) == deposit
    assert lido.balanceOf(xcWSTDOT) == 0
    assert localAsset.balanceOf(accounts[0]) == 0


def test_wrap_after_rewards(lido, oracle_master, vKSM, accounts, xcWSTDOT, localAsset):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()

    reward = 2 * 10**18
    relay.new_era([reward])

    lido.approve(xcWSTDOT, deposit // 2, {'from': accounts[0]})
    xcWSTDOT.wrap(deposit // 2, {'from': accounts[0]})

    assert localAsset.balanceOf(accounts[0]) == lido.sharesOf(xcWSTDOT)

    xcWSTDOT.unwrap(localAsset.balanceOf(accounts[0]), {'from': accounts[0]})

    assert localAsset.balanceOf(accounts[0]) == 0


def test_wrap_after_slashing(lido, oracle_master, vKSM, accounts, xcWSTDOT, localAsset):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()
    relay.new_era()

    loss = -2 * 10**18
    relay.new_era([loss])

    lido.approve(xcWSTDOT, deposit // 2, {'from': accounts[0]})
    xcWSTDOT.wrap(deposit // 2, {'from': accounts[0]})

    assert localAsset.balanceOf(accounts[0]) == lido.sharesOf(xcWSTDOT)

    xcWSTDOT.unwrap(localAsset.balanceOf(accounts[0]), {'from': accounts[0]})

    assert localAsset.balanceOf(accounts[0]) == 0


def test_submit_unwrap(lido, oracle_master, vKSM, accounts, xcWSTDOT, localAsset):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()

    vKSM.approve(xcWSTDOT, deposit // 2, {'from': accounts[0]})
    xcWSTDOT.submit(deposit // 2, {'from': accounts[0]})

    assert lido.balanceOf(accounts[0]) == deposit
    assert lido.balanceOf(xcWSTDOT) == deposit // 2
    assert localAsset.balanceOf(accounts[0]) == deposit // 2

    localAsset.approve(accounts[2], deposit // 2, {'from': accounts[0]})
    localAsset.transferFrom(accounts[0], accounts[2], deposit // 2, {'from': accounts[2]})

    xcWSTDOT.unwrap(deposit // 2, {'from': accounts[2]})

    assert lido.balanceOf(accounts[0]) == deposit
    assert lido.balanceOf(xcWSTDOT) == 0
    assert localAsset.balanceOf(accounts[0]) == 0