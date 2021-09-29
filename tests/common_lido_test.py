from brownie import reverts

MUNIT = 1_000_000
UNIT = 1_000_000_000


def test_fee_distribution(vKSM, LedgerMock, mocklido, mockledger, treasury, developers, admin):
    assert mocklido.balanceOf(admin) == 0
    vKSM.approve(mocklido, 10*UNIT, {'from': admin})
    mocklido.deposit(10 * UNIT, {'from': admin})

    assert mocklido.balanceOf(admin) == 10 * UNIT

    assert mocklido.balanceOf(treasury) == 0
    assert mocklido.balanceOf(developers) == 0

    assert mocklido.getFee() == 1000
    # call lido.distributeRewards via mock Ledger
    mockledger.distributeRewards(1*UNIT, {'from': admin})

    balance = mocklido.balanceOf(admin)
    assert balance == 10_900 * MUNIT  # +900 MUNIT (90%)
    balance = mocklido.balanceOf(treasury)
    assert balance == 39999999  # ~40 MUNIT (4%)
    balance = mocklido.balanceOf(developers)
    assert balance == 9999998   # ~10 MUNIT (1%)
    balance = mocklido.balanceOf(mocklido)
    assert balance == 50000001  # ~50 MUNIT (5%)


def test_fee_change_distribution(vKSM, LedgerMock, mocklido, mockledger, treasury, developers, admin):
    vKSM.approve(mocklido, 10 * UNIT, {'from': admin})
    mocklido.deposit(10 * UNIT, {'from': admin})

    assert mocklido.balanceOf(admin) == 10 * UNIT
    # call lido.distributeRewards via mock Ledger
    mocklido.setFee(1000, 0, 0, 10000)
    mockledger.distributeRewards(1*UNIT, {'from': admin})

    assert mocklido.balanceOf(treasury) == 0
    assert mocklido.balanceOf(developers) == 99999999  # ~100 MUNIT (10%)

    mocklido.setFee(1000, 0, 10000, 0)
    # call lido.distributeRewards via mock Ledger
    mockledger.distributeRewards(1*UNIT, {'from': admin})

    assert mocklido.balanceOf(treasury) == 99999999     # ~100 MUNIT (10%)
    assert mocklido.balanceOf(developers) == 108181817  # +~9%

    with reverts("LIDO: FEE_TOO_HIGH"):
        mocklido.setFee(2000, 0, 10000, 0)

    with reverts("LIDO: FEES_DONT_ADD_UP"):
        mocklido.setFee(1000, 8000, 2000, 1000)
