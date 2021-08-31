import pytest
from brownie import chain
from helpers import RelayChain, distribute_initial_tokens


def test_add_multi_ledgers(lido, oracle_master, vKSM, Ledger, accounts):
    for stash in (0x10, 0x20, 0x30):
        lido.addLedger(hex(stash), hex(stash + 1), 100, {'from': accounts[0]})
        ledger = Ledger.at(lido.findLedger(hex(stash)))
        assert ledger.stashAccount() == hex(stash)


def test_deposit_distribution(lido, oracle_master, vKSM, Ledger, accounts):
    stashes = [0x10, 0x20, 0x30]
    shares = [100, 50, 10]
    total_shares = sum(i for i in shares)
    total_deposit = 0

    def check_distribution():
        for i in range(len(stashes)):
            stash = hex(stashes[i])
            ledger = Ledger.at(lido.findLedger(stash))
            assert ledger.targetStake() == total_deposit * shares[i] // total_shares

    for i in range(len(stashes)):
        stash = stashes[i]
        lido.addLedger(hex(stash), hex(stash + 1), shares[i], {'from': accounts[0]})

    distribute_initial_tokens(vKSM, lido, accounts)

    #first deposit
    deposit = 1000 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[0]})
    check_distribution()

    #one another deposit
    deposit = 9905 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[1]})
    check_distribution()

    #change ledgers shares
    shares = [10, 500, 100]    
    total_shares = sum(i for i in shares)
    for i in range(len(stashes)):
        stash = stashes[i]
        lido.setLedgerShare(lido.findLedger(hex(stashes[i])), shares[i])
    check_distribution()


def test_change_shares_distribution(lido, oracle_master, vKSM, Ledger, accounts):
    stashes = [0x10, 0x20, 0x30]
    shares = [100, 50, 10]
    total_shares = sum(i for i in shares)
    total_deposit = 0

    def check_distribution():
        for i in range(len(stashes)):
            stash = hex(stashes[i])
            ledger = Ledger.at(lido.findLedger(stash))
            assert ledger.targetStake() == total_deposit * shares[i] // total_shares

    for i in range(len(stashes)):
        stash = stashes[i]
        lido.addLedger(hex(stash), hex(stash + 1), shares[i], {'from': accounts[0]})

    distribute_initial_tokens(vKSM, lido, accounts)

    #first deposit
    deposit = 1000 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[0]})
    check_distribution()

    #change ledgers shares
    shares = [10, 500, 100]    
    total_shares = sum(i for i in shares)
    for i in range(len(stashes)):
        stash = stashes[i]
        lido.setLedgerShare(lido.findLedger(hex(stashes[i])), shares[i])
    check_distribution()


def test_redeem_distribution(lido, oracle_master, vKSM, Ledger, accounts):
    stashes = [0x10, 0x20, 0x30]
    shares = [100, 50, 10]
    total_shares = sum(i for i in shares)
    total_deposit = 0

    def check_distribution():
        for i in range(len(stashes)):
            stash = hex(stashes[i])
            ledger = Ledger.at(lido.findLedger(stash))
            assert ledger.targetStake() == total_deposit * shares[i] // total_shares

    for i in range(len(stashes)):
        stash = stashes[i]
        lido.addLedger(hex(stash), hex(stash + 1), shares[i], {'from': accounts[0]})

    distribute_initial_tokens(vKSM, lido, accounts)

    #first deposit
    deposit = 1000 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[0]})
    check_distribution()

    total_deposit -= deposit // 2
    lido.redeem(deposit // 2, {'from': accounts[0]})
    check_distribution()