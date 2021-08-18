import pytest
from brownie import chain
from helpers import RelayChain, distribute_initial_tokens




def test_upward_transfer_mock(vKSM, accounts):
    before = vKSM.balanceOf(accounts[0])

    tx = vKSM.relayTransferTo("123", 123, {'from': accounts[0]})
    tx.info()
    
    assert tx.events['UpwardTransfer'][0]['amount'] == 123
    assert tx.events['UpwardTransfer'][0]['from'] == accounts[0]
    assert tx.events['UpwardTransfer'][0]['to'] == "0x123"

    assert vKSM.balanceOf(accounts[0]) == before - 123


def test_downward_transfer_mock(vKSM, vAccounts, accounts):
    before = vKSM.balanceOf(accounts[0])

    tx = vAccounts.relayTransferFrom("123", 123, {'from': accounts[0]})
    #tx.info()
    
    assert tx.events['DownwardTransfer'][0]['amount'] == 123
    assert tx.events['DownwardTransfer'][0]['from'] == "0x123"
    assert tx.events['DownwardTransfer'][0]['to'] == accounts[0]

    assert vKSM.balanceOf(accounts[0]) == before


def test_add_stash(lido, oracle, vKSM, Ledger, accounts):
    lido.addStash("0x10", "0x20", {'from': accounts[0]})

    legder = Ledger.at(lido.findLedger("0x10"))
    assert legder.stashAccount() == "0x10"
    assert legder.controllerAccount() == "0x20"


def test_single_deposit(lido, oracle, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle, accounts)
    relay.new_ledger("0x10", "0x11")
  
    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()

    assert relay.ledgers[0].free_balance == deposit
    assert relay.ledgers[0].active_balance == 0

    reward = 123
    relay.new_era([reward])
    assert relay.ledgers[0].active_balance == deposit + reward
    assert lido.getTotalPooledKSM() == deposit + reward


def test_multi_deposit(lido, oracle, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle, accounts)
    relay.new_ledger("0x10", "0x11")
  
    deposit1 = 20 * 10**18
    deposit2 = 5 * 10**18
    deposit3 = 100 * 10**18
    lido.deposit(deposit1, {'from': accounts[0]})
    lido.deposit(deposit2, {'from': accounts[1]})
    lido.deposit(deposit3, {'from': accounts[2]})

    relay.new_era()

    assert relay.ledgers[0].free_balance == deposit1 + deposit2 + deposit3
    assert relay.ledgers[0].active_balance == 0

    reward = 3 * 10**18
    relay.new_era([reward])
    assert relay.ledgers[0].active_balance == deposit1 + deposit2 + deposit3 + reward
    assert lido.getTotalPooledKSM() == deposit1 + deposit2 + deposit3 + reward

    acc1_balance = lido.balanceOf(accounts[0])
    acc2_balance = lido.balanceOf(accounts[1])
    acc3_balance = lido.balanceOf(accounts[2])
    lido_rewards = lido.balanceOf(lido)

    assert abs(acc1_balance + acc2_balance + acc3_balance + lido_rewards - lido.getTotalPooledKSM()) <= 1000


def test_redeem(lido, oracle, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle, accounts)
    relay.new_ledger("0x10", "0x11")

    deposit1 = 20 * 10**18
    deposit2 = 5 * 10**18
    deposit3 = 100 * 10**18
    lido.deposit(deposit1, {'from': accounts[0]})
    lido.deposit(deposit2, {'from': accounts[1]})
    lido.deposit(deposit3, {'from': accounts[2]})

    relay.new_era()

    reward = 3 * 10**18
    relay.new_era([reward])
    assert relay.ledgers[0].active_balance == deposit1 + deposit2 + deposit3 + reward
    assert lido.getTotalPooledKSM() == deposit1 + deposit2 + deposit3 + reward

    lido.redeem(lido.balanceOf(accounts[1]), {'from': accounts[1]})
    relay.new_era([reward])
    
    # travel for 29 eras
    relay.timetravel(29)
    chain.sleep(29 * 24 * 60 * 60)

    relay.new_era([reward]) # should send 'withdraw'
    relay.new_era([reward]) # should downward transfer
    relay.new_era([reward]) # should downward transfer got completed

    lido.claimUnbonded({'from': accounts[1]})
