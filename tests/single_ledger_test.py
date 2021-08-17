import pytest


def test_upward_transfer_mock(vKSM, accounts):
    assert vKSM.balanceOf(accounts[0]) == 10**24

    tx = vKSM.relayTransferTo("123", 123, {'from': accounts[0]})
    tx.info()
    
    assert tx.events['UpwardTransfer'][0]['amount'] == 123
    assert tx.events['UpwardTransfer'][0]['from'] == accounts[0]
    assert tx.events['UpwardTransfer'][0]['to'] == "0x123"

    assert vKSM.balanceOf(accounts[0]) == 10**24 - 123


def test_downward_transfer_mock(vKSM, vAccounts, accounts):
    assert vKSM.balanceOf(accounts[0]) == 10**24

    tx = vAccounts.relayTransferFrom("123", 123, {'from': accounts[0]})
    #tx.info()
    
    assert tx.events['DownwardTransfer'][0]['amount'] == 123
    assert tx.events['DownwardTransfer'][0]['from'] == "0x123"
    assert tx.events['DownwardTransfer'][0]['to'] == accounts[0]

    assert vKSM.balanceOf(accounts[0]) == 10**24


def test_add_stash(lido, oracle, vKSM, Ledger, accounts):
    lido.addStash("0x10", "0x20", {'from': accounts[0]})

    legder = Ledger.at(lido.findLedger("0x10"))
    assert legder.stashAccount() == "0x10"
    assert legder.controllerAccount() == "0x20"


def test_deposit(lido, oracle, vKSM, accounts):
    lido.addStash("0x10", "0x20", {'from': accounts[0]})

    deposit = 100 * 10**18;
    vKSM.approve(lido, 10**24, {'from': accounts[0]})
    lido.deposit(deposit, {'from': accounts[0]})

    assert lido.balanceOf(accounts[0]) == deposit

    oracle.addOracleMember(accounts[0], {'from': accounts[0]})
    oracle.setQuorum(1, {'from': accounts[0]})

    era = 2
    active_balance = 0
    free_balance = 0
    oracle.reportRelay(era, ('0x10', '0x20', 1, active_balance, active_balance, [], [], active_balance + free_balance)).info()

    era += 1
    free_balance = deposit
    active_balance += 111
    oracle.reportRelay(era, ('0x10', '0x20', 1, active_balance, active_balance, [], [], active_balance + free_balance)).info()

    era += 1
    active_balance += free_balance + 123
    free_balance = 0
    oracle.reportRelay(era, ('0x10', '0x20', 1, active_balance, active_balance, [], [], active_balance + free_balance)).info()

    era += 1
    active_balance -= 123
    free_balance = 0
    oracle.reportRelay(era, ('0x10', '0x20', 1, active_balance, active_balance, [], [], active_balance + free_balance)).info()



def test_redeem(lido, oracle, vKSM, accounts):
    lido.addStash("0x10", "0x20", {'from': accounts[0]})

    deposit = 100 * 10**18;
    vKSM.approve(lido, 10**24, {'from': accounts[0]})
    lido.deposit(deposit, {'from': accounts[0]})

    assert lido.balanceOf(accounts[0]) == deposit

    oracle.addOracleMember(accounts[0], {'from': accounts[0]})
    oracle.setQuorum(1, {'from': accounts[0]})

    era = 2
    active_balance = 0
    free_balance = 0
    oracle.reportRelay(era, ('0x10', '0x20', 1, active_balance, active_balance, [], [], active_balance + free_balance)).info()

    era += 1
    free_balance = deposit
    oracle.reportRelay(era, ('0x10', '0x20', 1, active_balance, active_balance, [], [], active_balance + free_balance)).info()

    era += 1
    active_balance += free_balance
    free_balance = 0
    oracle.reportRelay(era, ('0x10', '0x20', 1, active_balance, active_balance, [], [], active_balance + free_balance)).info()


    lido.redeem(deposit, {'from': accounts[0]})
    era += 1
    oracle.reportRelay(era, ('0x10', '0x20', 1, active_balance, active_balance, [], [], active_balance + free_balance)).info()

    st_balance = lido.balanceOf(accounts[0])
    lido.redeem(st_balance, {'from': accounts[0]})
    era += 1
    active_balance -= st_balance
    oracle.reportRelay(era, ('0x10', '0x20', 1, active_balance, active_balance, [(st_balance, era)], [], active_balance + free_balance)).info()