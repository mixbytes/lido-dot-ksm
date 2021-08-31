import pytest
from brownie import chain, Ledger
from helpers import RelayChain, distribute_initial_tokens

def check_distribution(lido, stashes, shares, total_deposit):
    total_shares = sum(i for i in shares)
    for i in range(len(stashes)):
        stash = hex(stashes[i])
        ledger = Ledger.at(lido.findLedger(stash))
        assert ledger.targetStake() == total_deposit * shares[i] // total_shares


def test_add_ledger_slowly(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)
    stashes = [0x10]
    shares = [100]
    total_deposit = 0

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger(hex(stashes[0]), hex(stashes[0]+1), shares[0])

    deposit = 1000 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[0]})
    check_distribution(lido, stashes, shares, total_deposit)

    rewards = 3 * 10**18
    relay.new_era([rewards])
    relay.new_era([rewards])

    assert relay.ledgers[0].active_balance == relay.total_rewards + total_deposit

    # new stash
    stashes.append(0x20)
    shares.append(50)
    relay.new_ledger(hex(stashes[1]), hex(stashes[1]+1), shares[1])
  
    # check target stake distribution
    check_distribution(lido, stashes, shares, total_deposit + relay.total_rewards)
    relay.new_era() # send unbond for first ledger
    relay.timetravel(29) # wait for unbonding period
    relay.new_era() # send withdraw for first ledger
    relay.new_era() # downward transfer from first ledger
    relay.new_era() # upward transfer for second ledger
    relay.new_era() # bond for first ledger

    assert relay.ledgers[0].active_balance == Ledger.at(lido.findLedger(hex(stashes[0]))).targetStake()
    assert relay.ledgers[1].active_balance == Ledger.at(lido.findLedger(hex(stashes[1]))).targetStake()


def test_remove_ledger_slowly(lido, oracle_master, vKSM, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)
    stashes = [0x10, 0x20]
    shares = [100, 50]
    total_deposit = 0

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger(hex(stashes[0]), hex(stashes[0]+1), shares[0])
    relay.new_ledger(hex(stashes[1]), hex(stashes[1]+1), shares[1])

    deposit = 1000 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[0]})
    check_distribution(lido, stashes, shares, total_deposit)

    rewards = 3 * 10**18
    relay.new_era([rewards, rewards]) # upward transfer
    relay.new_era([rewards, rewards]) # bond

    assert relay.ledgers[0].active_balance == total_deposit * 100 // 150 + 2*rewards

    # set zero share for ledger
    shares[1] = 0
    lido.setLedgerShare(relay.ledgers[1].ledger_address, 0, {'from': accounts[0]})
  
    # check target stake distribution
    check_distribution(lido, stashes, shares, total_deposit + relay.total_rewards)

    relay.new_era([rewards, rewards // 2]) # send unbond for second ledger
    assert relay.ledgers[1].status == 'Chill'

    relay.timetravel(29) # wait for unbonding period

    relay.new_era([rewards]) # send withdraw for second ledger

    relay.new_era([rewards]) # downward transfer from second ledger
    relay.new_era([rewards]) # upward transfer for first ledger
    relay.new_era([rewards]) # bondextra for fisrt ledger
    relay.new_era([rewards]) # bondextra for fisrt ledger [it depend on oracle_masterReport order accross ledgers]

    assert relay.ledgers[0].active_balance == Ledger.at(lido.findLedger(hex(stashes[0]))).targetStake()
    assert relay.ledgers[1].active_balance == Ledger.at(lido.findLedger(hex(stashes[1]))).targetStake()
    assert relay.ledgers[1].active_balance == 0
    assert relay.total_rewards + total_deposit == lido.getTotalPooledKSM()