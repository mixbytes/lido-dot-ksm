from brownie import chain
from helpers import RelayChain, distribute_initial_tokens
import pytest

def test_stake_collision(lido, oracle_master, vKSM, Ledger, accounts):
    # Create 2 ledgers with shares = (10, 1000)
    stashes = [0x10, 0x20]
    distribute_initial_tokens(vKSM, lido, accounts)
    for i in range(len(stashes)):
        stash = stashes[i]
        lido.addLedger(hex(stash), hex(stash + 1), 0, {'from': accounts[0]})

    # era 0
    # deposit 1010 vKSM
    deposit = 1010 * 10**18
    lido.deposit(deposit, {'from': accounts[0]})
    lido.flushStakes({'from': oracle_master})
    def ledger_stakes():
        for i in range(len(stashes)):
                stash = hex(stashes[i])
                ledger = Ledger.at(lido.findLedger(stash))
                print('ledger ' + str(i) + ' stake = ' + str(ledger.ledgerStake() / 10**18))
        print()
    # Check current ledger stakes
    ledger_stakes()

    # era 1
    # Redeem 20 vKSM
    lido.redeem(20 * 10**18, {'from': accounts[0]})
    # Receive report from ledger 2 with 20 rewards (Note: ledger stake doesn't increased, because 0 shares of ledger)
    lido.distributeRewards(20 * 10**18, 1020 * 10**18, {'from': lido.findLedger(stashes[1])})
    ledger_stakes()

    # era 2
    lido.flushStakes({'from': oracle_master})
    # check stake for ledger 1
    ledger_stakes()

    # Redeem 20 vKSM
    lido.redeem(20 * 10**18, {'from': accounts[0]})
    # era 3
    lido.flushStakes({'from': oracle_master})
    # check stake for ledger 1
    ledger_stakes()
