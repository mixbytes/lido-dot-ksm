from brownie import reverts

MUNIT = 1_000_000
UNIT = 1_000_000_000


def test_fee_distribution(vKSM, LedgerMock, mocklido, mockledger, treasury, developers, admin):
    '''
    Use default fee distribution:
    total 10% fee spleets between operators 3%, treasury 5.6%  and developers 1.4%
    '''
    assert mocklido.balanceOf(admin) == 0
    vKSM.approve(mocklido, 10*UNIT, {'from': admin})
    mocklido.deposit(10 * UNIT, {'from': admin})

    assert mocklido.balanceOf(admin) == 10 * UNIT

    assert mocklido.balanceOf(treasury) == 0
    assert mocklido.balanceOf(developers) == 0

    assert mocklido.getFee() == 1000
    # call lido.distributeRewards via mock Ledger
    t = mockledger.distributeRewards(1*UNIT, {'from': admin})
    print(t.info())

    balance = mocklido.balanceOf(admin)
    assert balance == 10_927_835_052  # +927 MUNIT (90% gives ~92.78%)
    balance = mocklido.balanceOf(treasury)
    assert balance == 57_731_958  # ~57.7 MUNIT (fee 5.6% gives ~5.77% of rewards)
    balance = mocklido.balanceOf(developers)
    assert balance == 14_432_989   # ~14.3 MUNIT (fee 1.4% gives ~ 1.43%)
    balance = mocklido.balanceOf(mocklido)
    assert balance == 0  # remains unchanged


def test_fee_change_distribution(vKSM, LedgerMock, mocklido, mockledger, treasury, developers, admin):
    vKSM.approve(mocklido, 10 * UNIT, {'from': admin})
    mocklido.deposit(10 * UNIT, {'from': admin})

    assert mocklido.balanceOf(admin) == 10 * UNIT
    # call lido.distributeRewards via mock Ledger
    mocklido.setFee(300, 0, 700)
    # assert mocklido.FEE_BP() == 0x0

    assert mocklido.balanceOf(treasury) == 0
    t = mockledger.distributeRewards(1*UNIT, {'from': admin})

    print(t.info())

    assert mocklido.balanceOf(treasury) == 0
    assert mocklido.balanceOf(developers) == 72_164_947  # ~72.1 MUNIT (7% gives 7.21% of 97%)

    mocklido.setFee(300, 700, 0)
    # call lido.distributeRewards via mock Ledger
    mockledger.distributeRewards(1*UNIT, {'from': admin})

    assert mocklido.balanceOf(treasury) == 72_164_946    # ~72.1 MUNIT (7% gives 7.21% of 97%)
    assert mocklido.balanceOf(developers) == 78_251_962

    with reverts("LIDO: FEE_DONT_ADD_UP"):
        mocklido.setFee(200, 0, 0)

    with reverts("LIDO: FEE_DONT_ADD_UP"):
        mocklido.setFee(2001, 2000, 6000)
