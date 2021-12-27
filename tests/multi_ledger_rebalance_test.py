from brownie import chain
from helpers import RelayChain, distribute_initial_tokens
import pytest


def test_add_multi_ledgers(lido, oracle_master, vKSM, Ledger, accounts):
    for stash in (0x10, 0x20, 0x30):
        lido.addLedger(hex(stash), hex(stash + 1), 0, {'from': accounts[0]})
        ledger = Ledger.at(lido.findLedger(hex(stash)))
        assert ledger.stashAccount() == hex(stash)


def test_deposit_distribution(lido, oracle_master, vKSM, Ledger, accounts):
    stashes = [0x10, 0x20, 0x30]
    total_deposit = 0

    def check_distribution():
        stakes_sum = 0
        for i in range(len(stashes)):
            stash = hex(stashes[i])
            ledger = Ledger.at(lido.findLedger(stash))
            stakes_sum += ledger.ledgerStake()
            target = total_deposit // len(stashes)
            assert abs(ledger.ledgerStake() - target) / target < 0.01
        assert stakes_sum == total_deposit

    for i in range(len(stashes)):
        stash = stashes[i]
        lido.addLedger(hex(stash), hex(stash + 1), 0, {'from': accounts[0]})

    distribute_initial_tokens(vKSM, lido, accounts)

    # first deposit
    deposit = 1000 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[0]})
    lido.flushStakes({'from': oracle_master})
    check_distribution()

    # one another deposit
    deposit = 9905 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[1]})
    lido.flushStakes({'from': oracle_master})
    check_distribution()


def test_redeem_distribution(lido, oracle_master, vKSM, Ledger, accounts):
    stashes = [0x10, 0x20, 0x30]
    total_deposit = 0

    def check_distribution():
        stakes_sum = 0
        for i in range(len(stashes)):
            stash = hex(stashes[i])
            ledger = Ledger.at(lido.findLedger(stash))
            stakes_sum += ledger.ledgerStake()
            target = total_deposit // len(stashes)
            assert abs(ledger.ledgerStake() - target) / target < 0.01
        assert stakes_sum == total_deposit

    for i in range(len(stashes)):
        stash = stashes[i]
        lido.addLedger(hex(stash), hex(stash + 1), 0, {'from': accounts[0]})

    distribute_initial_tokens(vKSM, lido, accounts)

    # first deposit
    deposit = 1000 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[0]})
    lido.flushStakes({'from': oracle_master})
    check_distribution()

    total_deposit -= deposit // 2
    lido.redeem(deposit // 2, {'from': accounts[0]})
    lido.flushStakes({'from': oracle_master})
    check_distribution()


@pytest.mark.skip_coverage
def test_huge_amount_ledgers(lido, oracle_master, vKSM, Ledger, accounts):
    LEDGER_AMOUNT = 60
    stashes = [i for i in range(LEDGER_AMOUNT)]
    total_deposit = 0

    def check_distribution():
        stakes_sum = 0
        for i in range(len(stashes)):
            stash = hex(stashes[i])
            ledger = Ledger.at(lido.findLedger(stash))
            stakes_sum += ledger.ledgerStake()
            target = total_deposit // len(stashes)
            assert abs(ledger.ledgerStake() - target) / target < 0.01
        assert stakes_sum == total_deposit

    for i in range(len(stashes)):
        stash = stashes[i]
        lido.addLedger(hex(stash), hex(stash + 1), 0, {'from': accounts[0]})

    distribute_initial_tokens(vKSM, lido, accounts)

    # first deposit
    deposit = 1000 * 10**18
    total_deposit += deposit
    lido.deposit(deposit, {'from': accounts[0]})
    tx = lido.flushStakes({'from': oracle_master})
    print('GAS USED:', tx.gas_used)
    check_distribution()


