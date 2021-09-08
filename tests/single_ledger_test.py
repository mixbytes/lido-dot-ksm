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


def test_add_stash(lido, oracle_master, vKSM, Ledger, accounts):
    lido.addLedger("0x10", "0x20", 100, {'from': accounts[0]})

    ledger = Ledger.at(lido.findLedger("0x10"))
    assert ledger.stashAccount() == "0x10"
    assert ledger.controllerAccount() == "0x20"


def test_single_deposit(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11", 100)
  
    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()

    assert relay.ledgers[0].free_balance == deposit
    assert relay.ledgers[0].active_balance == 0

    reward = 123
    relay.new_era([reward])
    assert relay.ledgers[0].active_balance == deposit + reward
    assert lido.getTotalPooledKSM() == deposit + reward


def test_multi_deposit(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11", 100)
  
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


def test_redeem(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11", 100)

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

    balance_for_redeem = lido.balanceOf(accounts[1])
    lido.redeem(balance_for_redeem, {'from': accounts[1]})
    relay.new_era([reward])
    
    # travel for 29 eras
    relay.timetravel(29)

    relay.new_era([reward]) # should send 'withdraw'
    relay.new_era([reward]) # should downward transfer
    relay.new_era([reward]) # should downward transfer got completed

    balance_before_claim = vKSM.balanceOf(accounts[1])
    lido.claimUnbonded({'from': accounts[1]})

    assert vKSM.balanceOf(accounts[1]) == balance_for_redeem + balance_before_claim
    assert lido.getTotalPooledKSM() == deposit1 + deposit2 + deposit3 + 5*reward - balance_for_redeem 


def test_multi_redeem(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11", 100)

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[1]})

    relay.new_era()

    assert relay.ledgers[0].free_balance == deposit
    assert relay.ledgers[0].active_balance == 0

    reward = 123
    relay.new_era([reward])
    assert relay.ledgers[0].active_balance == deposit + reward
    assert lido.getTotalPooledKSM() == deposit + reward

    redeem_1 = 5 * 10**18
    redeem_2 = 6 * 10**18
    redeem_3 = 7 * 10**18

    lido.redeem(redeem_1, {'from': accounts[1]})
    relay.new_era([reward])

    assert lido.getUnbonded(accounts[1]) == (redeem_1, 0)

    lido.redeem(redeem_2, {'from': accounts[1]})
    relay.new_era([reward])

    assert lido.getUnbonded(accounts[1]) == (redeem_1 + redeem_2, 0)

    lido.redeem(redeem_3, {'from': accounts[1]})
    relay.new_era([reward])

    assert lido.getUnbonded(accounts[1]) == (redeem_1 + redeem_2 + redeem_3, 0)

    # travel for 29 eras
    chain.sleep(1000)
    relay.timetravel(25)
    assert lido.getUnbonded(accounts[1]) == (redeem_2 + redeem_3, redeem_1)

    relay.timetravel(1)
    assert lido.getUnbonded(accounts[1]) == (redeem_3, redeem_1 + redeem_2)

    relay.timetravel(1)
    assert lido.getUnbonded(accounts[1]) == (0, redeem_1 + redeem_2 + redeem_3)

    relay.new_era([reward])
    relay.new_era([reward]) # should send 'withdraw'
    relay.new_era([reward]) # should downward transfer
    relay.new_era([reward]) # should downward transfer got completed

    balance_before_claim = vKSM.balanceOf(accounts[1])
    lido.claimUnbonded({'from': accounts[1]})

    assert vKSM.balanceOf(accounts[1]) == redeem_1 + redeem_2 + redeem_3 + balance_before_claim


def test_multi_redeem_order_removal(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11", 100)

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[1]})

    relay.new_era()

    assert relay.ledgers[0].free_balance == deposit
    assert relay.ledgers[0].active_balance == 0

    reward = 123
    relay.new_era([reward])
    assert relay.ledgers[0].active_balance == deposit + reward
    assert lido.getTotalPooledKSM() == deposit + reward

    redeem_1 = 5 * 10**18
    redeem_2 = 6 * 10**18
    redeem_3 = 7 * 10**18

    lido.redeem(redeem_1, {'from': accounts[1]})
    relay.new_era([reward])
    relay.timetravel(7)

    assert lido.getUnbonded(accounts[1]) == (redeem_1, 0)

    lido.redeem(redeem_2, {'from': accounts[1]})
    relay.new_era([reward])
    relay.timetravel(7)

    assert lido.getUnbonded(accounts[1]) == (redeem_1 + redeem_2, 0)

    lido.redeem(redeem_3, {'from': accounts[1]})
    relay.new_era([reward])
    relay.timetravel(7)

    assert lido.getUnbonded(accounts[1]) == (redeem_1 + redeem_2 + redeem_3, 0)

    relay.timetravel(5)
    assert lido.getUnbonded(accounts[1]) == (redeem_2 + redeem_3, redeem_1)

    relay.new_era([reward])
    relay.new_era([reward]) # should send 'withdraw'
    relay.new_era([reward]) # should downward transfer
    relay.new_era([reward]) # should downward transfer got completed

    balance_before_claim = vKSM.balanceOf(accounts[1])
    lido.claimUnbonded({'from': accounts[1]})

    assert vKSM.balanceOf(accounts[1]) == redeem_1 + balance_before_claim
    assert lido.getUnbonded(accounts[1]) == (redeem_2 + redeem_3, 0)


def test_multi_redeem_mixed_timeout(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11", 100)
    relay_spec_raw = lido.RELAY_SPEC()
    relay_spec_array = [relay_spec_raw[0], relay_spec_raw[1], relay_spec_raw[2], relay_spec_raw[3], relay_spec_raw[4]]

    deposit = 20 * 10**18
    lido.deposit(deposit, {'from': accounts[1]})

    redeem_1 = 5 * 10**18
    redeem_2 = 6 * 10**18
    redeem_3 = 7 * 10**18

    relay_spec_array[2] = 12000 # change unbonding peroid to 1000 secs
    lido.setRelaySpec(relay_spec_array, {'from': accounts[0]})
    lido.redeem(redeem_1, {'from': accounts[1]})

    relay_spec_array[2] = 8000
    lido.setRelaySpec(relay_spec_array, {'from': accounts[0]})
    lido.redeem(redeem_2, {'from': accounts[1]})

    relay_spec_array[2] = 2000
    lido.setRelaySpec(relay_spec_array, {'from': accounts[0]})
    lido.redeem(redeem_3, {'from': accounts[1]})
    chain.mine()

    assert lido.claimOrders(accounts[1], 0)[1] > lido.claimOrders(accounts[1], 1)[1]
    assert lido.claimOrders(accounts[1], 1)[1] > lido.claimOrders(accounts[1], 2)[1]
    assert lido.getUnbonded(accounts[1]) == (redeem_1 + redeem_2 + redeem_3, 0)

    chain.sleep(9000) # after that we can claim redeem_2, redeem_3
    chain.mine()
    assert lido.getUnbonded(accounts[1]) == (redeem_1, redeem_2 + redeem_3)
    lido.claimUnbonded({'from': accounts[1]})
    assert lido.getUnbonded(accounts[1]) == (redeem_1, 0) # redeem_2, redeem_3 are claimed, redeem_1 is remaining
    assert lido.claimOrders(accounts[1], 0)[0] == redeem_1