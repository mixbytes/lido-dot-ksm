from black import assert_equivalent
from brownie import chain
from helpers import RelayChain, distribute_initial_tokens
import pytest


# def test_redeem(lido, oracle_master, vKSM, withdrawal, accounts):
#     distribute_initial_tokens(vKSM, lido, accounts)

#     relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
#     relay.new_ledger("0x10", "0x11")

#     deposit1 = 20 * 10**12
#     deposit2 = 5 * 10**12
#     deposit3 = 100 * 10**12
#     lido.deposit(deposit1, {'from': accounts[0]})
#     lido.deposit(deposit2, {'from': accounts[1]})
#     lido.deposit(deposit3, {'from': accounts[2]})

#     relay.new_era()

#     reward = 3 * 10**12
#     relay.new_era([reward])
#     assert relay.ledgers[0].active_balance == deposit1 + deposit2 + deposit3 + reward
#     assert lido.getTotalPooledKSM() == deposit1 + deposit2 + deposit3 + reward

#     balance_for_redeem = lido.balanceOf(accounts[1])

#     lido.redeem(balance_for_redeem, {'from': accounts[1]})

#     relay.new_era([reward])

#     # travel for 28 eras
#     relay.timetravel(28) # wait unbonding

#     relay.new_era([reward])  # should send 'withdraw'
#     relay.new_era([reward])  # should downward transfer
#     relay.new_era([reward])  # should downward transfer got completed
#     relay.new_era()  # update era in withdrawal

#     withdrawal_vksm = vKSM.balanceOf(withdrawal)
#     assert withdrawal_vksm == balance_for_redeem

#     balance_before_claim = vKSM.balanceOf(accounts[1])
#     lido.claimUnbonded({'from': accounts[1]})

#     assert vKSM.balanceOf(accounts[1]) == balance_for_redeem + balance_before_claim
#     assert lido.getTotalPooledKSM() == deposit1 + deposit2 + deposit3 + 5*reward - balance_for_redeem


# @pytest.mark.skip_coverage
# def test_check_queue(lido, oracle_master, vKSM, withdrawal, accounts):
#     distribute_initial_tokens(vKSM, lido, accounts)

#     relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
#     relay.new_ledger("0x10", "0x11")

#     deposit = 20 * 10**12
#     lido.deposit(deposit, {'from': accounts[0]})
#     lido.deposit(deposit, {'from': accounts[1]})
#     lido.deposit(deposit, {'from': accounts[2]})
#     lido.deposit(deposit, {'from': accounts[3]})
#     lido.deposit(deposit, {'from': accounts[4]})

#     relay.new_era()
#     relay.new_era()

#     assert relay.ledgers[0].active_balance == deposit * 5

#     for j in range(5):
#         for i in range(20):
#             lido.redeem(10**12, {'from': accounts[j]})
#             relay.new_era()

#     # One more claim for check function 
#     balance_before_claim = vKSM.balanceOf(accounts[0])
#     lido.claimUnbonded({'from': accounts[0]})
#     balance_after_claim = vKSM.balanceOf(accounts[0])

#     for i in range(28):
#         relay.new_era() # wait unbonding for last redeem for last user
    
#     relay.new_era()  # should send 'withdraw'
#     relay.new_era()  # should downward transfer
#     relay.new_era()  # should downward transfer got completed
#     relay.new_era()  # update era in withdrawal

#     withdrawal_vksm = vKSM.balanceOf(withdrawal)
#     diff = balance_after_claim - balance_before_claim
#     assert withdrawal_vksm == (deposit * 5 - diff)

#     for i in range(1, 5):
#         balance_before_claim = vKSM.balanceOf(accounts[i])
#         lido.claimUnbonded({'from': accounts[i]})
#         assert vKSM.balanceOf(accounts[i]) == (deposit + balance_before_claim)


# def test_losses_distribution(lido, oracle_master, vKSM, withdrawal, accounts):
#     distribute_initial_tokens(vKSM, lido, accounts)
#     lido.setMaxAllowableDifference(51000, {'from': accounts[0]})

#     relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
#     relay.new_ledger("0x10", "0x11")

#     deposit = 100 * 10**12
#     lido.deposit(deposit, {'from': accounts[0]})

#     relay.new_era()
#     relay.new_era()

#     assert relay.ledgers[0].active_balance == deposit

#     redeem = 60 * 10**12
#     lido.redeem(redeem, {'from': accounts[0]})
#     relay.new_era()

#     lido_virtual_balance = lido.fundRaisedBalance()
#     withdrawal_virtual_balance = withdrawal.totalVirtualXcKSMAmount()

#     assert lido_virtual_balance == deposit - redeem
#     assert withdrawal_virtual_balance == redeem

#     assert relay.ledgers[0].total_balance() == deposit

#     losses = 51234567890377
#     relay.new_era([-losses])

#     assert relay.ledgers[0].total_balance() == deposit - losses

#     # travel for 28 eras
#     relay.timetravel(28) # wait unbonding

#     relay.new_era()  # should send 'withdraw'
#     relay.new_era()  # should downward transfer
#     relay.new_era()  # should downward transfer got completed
#     relay.new_era()  # update era in withdrawal

#     lido.claimUnbonded({'from': accounts[0]})

#     assert withdrawal.totalXcKSMPoolShares() == 0
#     assert withdrawal.totalVirtualXcKSMAmount() == 0
#     assert vKSM.balanceOf(withdrawal) <= 100
#     assert relay.ledgers[0].total_balance() == lido.totalSupply()
#     assert relay.ledgers[0].active_balance == lido.totalSupply()

#     lido.redeem(lido.balanceOf(accounts[0]), {'from': accounts[0]})
#     relay.new_era()

#     relay.timetravel(28) # wait unbonding

#     relay.new_era()  # should send 'withdraw'
#     relay.new_era()  # should downward transfer
#     relay.new_era()  # should downward transfer got completed
#     relay.new_era()  # update era in withdrawal

#     lido.claimUnbonded({'from': accounts[0]})

#     assert withdrawal.totalXcKSMPoolShares() == 0
#     assert withdrawal.totalVirtualXcKSMAmount() == 0
#     assert vKSM.balanceOf(withdrawal) <= 100
#     assert lido.totalSupply() == 0
#     assert relay.ledgers[0].total_balance() == lido.totalSupply()
#     assert relay.ledgers[0].active_balance == lido.totalSupply()


# @pytest.mark.skip_coverage
# def test_relay_block(lido, oracle_master, vKSM, withdrawal, Ledger, accounts):
#     distribute_initial_tokens(vKSM, lido, accounts)

#     relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
#     relay.new_ledger("0x10", "0x11")

#     deposit = 20 * 10**12
#     lido.deposit(deposit, {'from': accounts[0]})

#     relay.new_era()
#     relay.new_era()

#     assert relay.ledgers[0].active_balance == deposit

#     for i in range(15):
#         lido.redeem(10**12, {'from': accounts[0]})
#         relay.new_era()

#     withdrawal_vksm = vKSM.balanceOf(withdrawal)
#     assert withdrawal_vksm == 0

#     # Block xcm messages for 30 eras
#     relay.block_xcm_messages = True
#     for i in range(5):
#         lido.redeem(10**12, {'from': accounts[0]})
#         relay.new_era()
#         withdrawal_vksm = vKSM.balanceOf(withdrawal)
#         assert withdrawal_vksm == 0

#     # Unblock xcm messages
#     relay.block_xcm_messages = False

#     ledger = Ledger.at(relay.ledgers[0].ledger_address)
#     assert ledger.transferDownwardBalance() == 0
#     assert lido.ledgerStake(ledger.address) == 0

#     relay.new_era()

#     (waitingToUnbonding, readyToClaim) = lido.getUnbonded(accounts[0])

#     assert readyToClaim == 0
#     assert waitingToUnbonding == 20 * 10**12

#     for i in range(38): # wait 33 era + 5 for eras with blocked messages
#         relay.new_era() # wait unbonding for last redeem
    
#     relay.new_era()  # should send 'withdraw'
#     relay.new_era()  # should downward transfer
#     relay.new_era()  # should downward transfer got completed
#     relay.new_era()  # update era in withdrawal

#     withdrawal_vksm = vKSM.balanceOf(withdrawal)
#     assert withdrawal_vksm == deposit

#     balance_before_claim = vKSM.balanceOf(accounts[0])
#     lido.claimUnbonded({'from': accounts[0]})

#     assert vKSM.balanceOf(accounts[0]) == (deposit + balance_before_claim)


# def test_losses_distribution_with_fast_track(lido, oracle_master, vKSM, withdrawal, accounts):
#     distribute_initial_tokens(vKSM, lido, accounts)
#     lido.setMaxAllowableDifference(51000, {'from': accounts[0]})

#     relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
#     relay.new_ledger("0x10", "0x11")

#     deposit = 100 * 10**12
#     lido.deposit(deposit, {'from': accounts[0]})

#     relay.new_era()
#     relay.new_era()

#     assert relay.ledgers[0].active_balance == deposit

#     redeem = 60 * 10**12
#     lido.redeem(redeem, {'from': accounts[0]})
#     relay.new_era()

#     deposit_2 = 56678123504984
#     lido.deposit(deposit_2, {'from': accounts[1]})
#     relay.new_era()

#     lido_virtual_balance = lido.fundRaisedBalance()
#     withdrawal_virtual_balance = withdrawal.totalVirtualXcKSMAmount()

#     assert lido_virtual_balance == deposit + deposit_2 - redeem
#     assert withdrawal_virtual_balance == redeem

#     assert relay.ledgers[0].total_balance() == deposit

#     (waiting, available) = lido.getUnbonded(accounts[0])
#     print("Waiting = " + str(waiting / 10**12))

#     losses = 51234567890377
#     relay.new_era([-losses])

#     (waiting, available) = lido.getUnbonded(accounts[0])
#     print("Waiting = " + str(waiting / 10**12))


#     assert relay.ledgers[0].total_balance() == deposit - losses

#     # travel for 28 eras
#     relay.timetravel(28) # wait unbonding

#     relay.new_era()  # should send 'withdraw'
#     relay.new_era()  # should downward transfer
#     relay.new_era()  # should downward transfer got completed
#     relay.new_era()  # update era in withdrawal

#     lido.claimUnbonded({'from': accounts[0]})

#     assert withdrawal.totalXcKSMPoolShares() == 0
#     assert withdrawal.totalVirtualXcKSMAmount() == 0
#     assert vKSM.balanceOf(withdrawal) <= 100
#     assert relay.ledgers[0].total_balance() == lido.totalSupply()
#     assert relay.ledgers[0].active_balance == lido.totalSupply()

#     lido.redeem(lido.balanceOf(accounts[0]), {'from': accounts[0]})
#     lido.redeem(lido.balanceOf(accounts[1]), {'from': accounts[1]})
#     relay.new_era()

#     relay.timetravel(28) # wait unbonding

#     relay.new_era()  # should send 'withdraw'
#     relay.new_era()  # should downward transfer
#     relay.new_era()  # should downward transfer got completed
#     relay.new_era()  # update era in withdrawal

#     lido.claimUnbonded({'from': accounts[0]})
#     lido.claimUnbonded({'from': accounts[1]})

#     assert withdrawal.totalXcKSMPoolShares() == 0
#     assert withdrawal.totalVirtualXcKSMAmount() == 0
#     assert vKSM.balanceOf(withdrawal) <= 100
#     assert lido.totalSupply() < 10
#     assert relay.ledgers[0].total_balance() == lido.totalSupply()
#     assert relay.ledgers[0].active_balance == lido.totalSupply()


def test_losses_distribution_with_fast_track_2_ledgers(lido, oracle_master, vKSM, withdrawal, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)
    lido.setMaxAllowableDifference(51000, {'from': accounts[0]})

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")
    relay.new_ledger("0x20", "0x21")
    relay.new_ledger("0x30", "0x31")

    deposit = 1500 * 10**12
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()
    relay.new_era()

    redeem = 1350 * 10**12
    lido.redeem(redeem, {'from': accounts[0]})
    relay.new_era()

    deposit_2 = 1200 * 10**12
    lido.deposit(deposit_2, {'from': accounts[1]})
    relay.new_era()

    lido_virtual_balance = lido.fundRaisedBalance()
    withdrawal_virtual_balance = withdrawal.totalVirtualXcKSMAmount()

    assert lido_virtual_balance == deposit + deposit_2 - redeem
    assert withdrawal_virtual_balance == redeem

    (waiting, available) = lido.getUnbonded(accounts[0])
    print("Waiting = " + str(waiting / 10**12))

    losses = 400 * 10**12
    relay.new_era([-losses])

    (waiting, available) = lido.getUnbonded(accounts[0])
    print("Waiting = " + str(waiting / 10**12))

    # travel for 28 eras
    relay.timetravel(28) # wait unbonding

    relay.new_era()  # should send 'withdraw'
    relay.new_era()  # should downward transfer
    relay.new_era()  # should downward transfer got completed
    relay.new_era()  # update era in withdrawal

    lido.claimUnbonded({'from': accounts[0]})

    assert withdrawal.totalXcKSMPoolShares() == 0
    assert withdrawal.totalVirtualXcKSMAmount() == 0
    assert vKSM.balanceOf(withdrawal) <= 1000
    assert relay.ledgers[0].total_balance() == 90 * 10**12
    assert relay.ledgers[0].active_balance == 90 * 10**12
    assert relay.ledgers[1].total_balance() == 450 * 10**12
    assert relay.ledgers[1].active_balance == 450 * 10**12
    assert relay.ledgers[1].total_balance() == 450 * 10**12
    assert relay.ledgers[1].active_balance == 450 * 10**12

    lido.redeem(lido.balanceOf(accounts[0]), {'from': accounts[0]})
    lido.redeem(lido.balanceOf(accounts[1]), {'from': accounts[1]})
    relay.new_era()

    relay.timetravel(28) # wait unbonding

    relay.new_era()  # should send 'withdraw'
    relay.new_era()  # should downward transfer
    relay.new_era()  # should downward transfer got completed
    relay.new_era()  # update era in withdrawal

    lido.claimUnbonded({'from': accounts[0]})
    lido.claimUnbonded({'from': accounts[1]})

    assert withdrawal.totalXcKSMPoolShares() == 0
    assert withdrawal.totalVirtualXcKSMAmount() == 0
    assert vKSM.balanceOf(withdrawal) <= 1000
    assert lido.totalSupply() == 0
    assert relay.ledgers[0].total_balance() == lido.totalSupply()
    assert relay.ledgers[0].active_balance == lido.totalSupply()