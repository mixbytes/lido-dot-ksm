from brownie import chain
from helpers import RelayChain, distribute_initial_tokens


def test_deposit_redeem_with_disabled_oracle(lido, oracle_master, vKSM, withdrawal, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")
    relay.new_ledger("0x20", "0x21")
    relay.new_ledger("0x30", "0x31")

    deposit = 1500 * 10**12
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()
    relay.new_era()

    deposit = 600 * 10**12
    lido.deposit(deposit, {'from': accounts[0]})

    # last ledger didn't receive funds from Lido because oracle didn't reach quorum
    relay.new_era(blocked_quorum=[False, False, True])
    assert vKSM.balanceOf(lido) == 200 * 10**12

    redeem = 1200 * 10**12
    lido.redeem(redeem, {'from': accounts[0]})
    relay.new_era()

    # 200 xcKSM locked on Lido because oracle didn't send report last era
    assert vKSM.balanceOf(lido) == 0

    relay.timetravel(28) # wait unbonding

    relay.new_era()  # should send 'withdraw'
    relay.new_era()  # should downward transfer
    relay.new_era()  # should downward transfer got completed
    relay.new_era()  # update era in withdrawal

    lido.claimUnbonded({'from': accounts[0]})

    assert vKSM.balanceOf(withdrawal) == 0
    assert withdrawal.totalXcKSMPoolShares() == 0
    assert withdrawal.totalVirtualXcKSMAmount() == 0


def test_deposit_redeem_with_disabled_oracle_and_disabled_ledger(lido, oracle_master, vKSM, withdrawal, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")
    relay.new_ledger("0x20", "0x21")
    relay.new_ledger("0x30", "0x31")

    deposit = 1500 * 10**12
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()
    relay.new_era()

    deposit = 600 * 10**12
    lido.deposit(deposit, {'from': accounts[0]})

    # last ledger didn't receive funds from Lido because oracle didn't reach quorum
    relay.new_era(blocked_quorum=[False, False, True])
    assert vKSM.balanceOf(lido) == 200 * 10**12

    lido.disableLedger(relay.ledgers[2].ledger_address, {'from': accounts[0]})

    redeem = 1200 * 10**12
    lido.redeem(redeem, {'from': accounts[0]})
    relay.new_era()

    # 200 xcKSM locked on Lido because oracle didn't send report last era
    assert vKSM.balanceOf(lido) == 0

    relay.timetravel(28) # wait unbonding

    relay.new_era()  # should send 'withdraw'
    relay.new_era()  # should downward transfer
    relay.new_era()  # should downward transfer got completed
    relay.new_era()  # update era in withdrawal

    lido.claimUnbonded({'from': accounts[0]})

    assert vKSM.balanceOf(withdrawal) == 0
    assert withdrawal.totalXcKSMPoolShares() == 0
    assert withdrawal.totalVirtualXcKSMAmount() == 0


def test_redeem_deposit_with_disabled_oracle(lido, oracle_master, vKSM, withdrawal, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11")
    relay.new_ledger("0x20", "0x21")
    relay.new_ledger("0x30", "0x31")

    deposit = 1500 * 10**12
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()
    relay.new_era()

    redeem = 600 * 10**12
    lido.redeem(redeem, {'from': accounts[0]})

    # last ledger didn't receive funds from Lido because oracle didn't reach quorum
    relay.new_era(blocked_quorum=[False, False, True])
    assert vKSM.balanceOf(lido) == 0

    deposit = 900 * 10**12
    lido.deposit(deposit, {'from': accounts[0]})
    relay.new_era()

    # 200 xcKSM locked on Lido because oracle didn't send report last era
    assert vKSM.balanceOf(lido) == 0

    relay.timetravel(28) # wait unbonding

    relay.new_era()  # should send 'withdraw'
    relay.new_era()  # should downward transfer
    relay.new_era()  # should downward transfer got completed
    relay.new_era()  # update era in withdrawal

    lido.claimUnbonded({'from': accounts[0]})

    assert vKSM.balanceOf(withdrawal) == 0
    assert withdrawal.totalXcKSMPoolShares() == 0
    assert withdrawal.totalVirtualXcKSMAmount() == 0