from brownie import chain, reverts
from helpers import RelayChain, distribute_initial_tokens
import pytest

def test_check_info(lido, LedgerProxy, LedgerBeacon, accounts):
    beacon = LedgerBeacon.at(lido.LEDGER_BEACON())
    for stash in (0x10, 0x20, 0x30):
        lido.addLedger(hex(stash), hex(stash + 1), 0, {'from': accounts[0]})
        ledgerProxy = LedgerProxy.at(lido.findLedger(hex(stash)))
        assert ledgerProxy.beaconAddress() == beacon

    assert beacon.currentRevision() == 1
    assert beacon.currentRevision() == beacon.latestRevision()


def test_update_revision(lido, LedgerBeacon, LedgerMock, accounts):
    beacon = LedgerBeacon.at(lido.LEDGER_BEACON())
    ledgers = []

    for stash in (0x10, 0x20, 0x30):
        lido.addLedger(hex(stash), hex(stash + 1), 0, {'from': accounts[0]})
        ledgers.append(LedgerMock.at(lido.findLedger(hex(stash))))
        assert ledgers[-1].LIDO() == lido

    # add new implementation to beacon
    ledger_mock = LedgerMock.deploy({'from': accounts[0]})
    beacon.addImplementation(ledger_mock, {'from': accounts[0]})

    # update implementation for ledger
    ledger_for_update = ledgers[1]
    beacon.setLedgerRevision(ledger_for_update, 2, {'from': accounts[0]})

    # call function from updated revision
    ledger_for_update.distributeRewards(10**9, 0, {'from': accounts[0]})

    # call from old revision will fail because old version doesn't have distributeRewards() method
    ledger_old_rev = ledgers[0]
    with reverts():
        ledger_old_rev.distributeRewards(10**9, 0, {'from': accounts[0]})

    # set new revision for all ledgers
    beacon.setCurrentRevision(2, {'from': accounts[0]})

    # now must work because we update  revision
    ledger_old_rev.distributeRewards(10**9, 0, {'from': accounts[0]})