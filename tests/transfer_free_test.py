from brownie import chain
from helpers import RelayChain, distribute_initial_tokens
import pytest


def test_deposit_distribution(lido, oracle_master, vKSM, Ledger, withdrawal, accounts):
    distribute_initial_tokens(vKSM, lido, accounts)
    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)

    stashes = [0x10, 0x20, 0x30, 0x40]

    for i in range(len(stashes)):
        stash = stashes[i]
        relay.new_ledger(hex(stash), hex(stash + 1))

    relay.new_era()

    # working system for 4 ledgers
    deposit = 20000 * 10**12
    lido.deposit(deposit, {'from': accounts[0]})

    relay.new_era()
    relay.new_era()

    assert relay.ledgers[0].free_balance == 0
    assert relay.ledgers[0].active_balance == deposit // 4

    # adding new ledger
    stash = 0x50
    relay.new_ledger(hex(stash), hex(stash + 1))

    relay.new_era()

    # redeem
    redeem = 4000 * 10**12
    lido.redeem(redeem, {'from': accounts[0]})
    relay.new_era()

    assert relay.ledgers[0].free_balance == 0
    assert relay.ledgers[0].active_balance == (deposit - redeem) // 4

    # another deposit
    deposit_2 = 10000 * 10**12
    lido.deposit(deposit_2, {'from': accounts[0]})
    relay.new_era()

    assert relay.ledgers[4].free_balance == (deposit + deposit_2 - redeem) // 5

    ledger_free = (deposit + deposit_2 - redeem) // 5 - deposit // 4
    assert relay.ledgers[0].free_balance == ledger_free
    assert relay.ledgers[0].active_balance == deposit // 4

    # redeem
    redeem_2 = 5000 * 10**12
    lido.redeem(redeem_2, {'from': accounts[0]})
    relay.new_era()

    ledger = Ledger.at(relay.ledgers[0].ledger_address)
    assert ledger.transferDownwardBalance() == ledger_free

    # deposit
    deposit_3 = 5000 * 10**12
    lido.deposit(deposit_3, {'from': accounts[0]})
    relay.new_era()
