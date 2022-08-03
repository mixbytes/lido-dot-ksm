from brownie import reverts

MUNIT = 1_000_000
UNIT = 1_000_000_000

def test_lido_new_name_revert(lido):
    with reverts("LIDO: NAME_SETTED"):
        lido.setTokenInfo("TST", "TST", 12)


def test_fee_distribution(vKSM, LedgerMock, mocklido, mockledger, treasury, developers, admin):
    '''
    Use default fee distribution:
    total 10% fee splits between operators 3%, treasury 5.6%  and developers 1.4%
    '''
    assert mocklido.balanceOf(admin) == 0
    vKSM.approve(mocklido, 10*UNIT, {'from': admin})
    mocklido.deposit(10 * UNIT, {'from': admin})

    assert mocklido.balanceOf(admin) == 10 * UNIT

    assert mocklido.balanceOf(treasury) == 0
    assert mocklido.balanceOf(developers) == 0

    beacon = mocklido.LEDGER_BEACON()
    print(beacon)

    # call lido.distributeRewards via mock Ledger
    # 1 UNIT has already withdrawn operators (3%) fee
    t = mockledger.distributeRewards(1*UNIT, 0, {'from': admin})
    print(t.info())

    balance = mocklido.balanceOf(admin)
    assert balance == 10_900_000_000  # +900 MUNIT (90%)
    balance = mocklido.balanceOf(treasury)
    assert balance == 80_000_000  # 80 MUNIT (fee 8%)
    balance = mocklido.balanceOf(developers)
    assert balance == 19_999_999   # ~20 MUNIT (fee 2%)
    balance = mocklido.balanceOf(mocklido)
    assert balance == 0  # remains unchanged


def test_fee_change_distribution(vKSM, LedgerMock, mocklido, mockledger, treasury, developers, admin):
    vKSM.approve(mocklido, 10 * UNIT, {'from': admin})
    mocklido.deposit(10 * UNIT, {'from': admin})

    assert mocklido.balanceOf(admin) == 10 * UNIT
    # call lido.distributeRewards via mock Ledger
    mocklido.setFee(300, 0, 700)

    assert mocklido.balanceOf(treasury) == 0
    t = mockledger.distributeRewards(1*UNIT, 0, {'from': admin})

    print(t.info())

    assert mocklido.balanceOf(treasury) == 0
    assert mocklido.balanceOf(developers) == 72_164_947  # ~72.1 MUNIT (7% gives 7.21% of 97%)

    mocklido.setFee(300, 700, 0)
    # call lido.distributeRewards via mock Ledger
    # 1 UNIT has already withdrawn operators (3%) fee
    mockledger.distributeRewards(1*UNIT, 0, {'from': admin})

    assert mocklido.balanceOf(treasury) == 72_164_946    # ~72.1 MUNIT (7% gives 7.21% of 97%)
    assert mocklido.balanceOf(developers) == 78_251_962

    with reverts("LIDO: FEE_DONT_ADD_UP"):
        mocklido.setFee(200, 0, 0)

    with reverts("LIDO: FEE_DONT_ADD_UP"):
        mocklido.setFee(2001, 2000, 6000)


def test_change_cap(lido, accounts):
    cap = 100 * 10**12
    lido.setDepositCap(100 * 10**12, {'from': accounts[0]})
    assert lido.depositCap() == cap
