import math
import brownie

from brownie import chain
from helpers import RelayChain, distribute_initial_tokens


def test_forced_unbond(
        lido,
        oracle_master,
        proxy_admin,
        wstKSM,
        vKSM,
        Lido,
        LidoUnbond,
        Ledger,
        accounts
    ):
    ########################
    #  Initial test setup  #
    ########################
    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)

    relay.new_ledger("0x10", "0x11")
    relay.new_ledger("0x20", "0x21")
    relay.new_ledger("0x30", "0x31")

    n_accounts = len(accounts)

    wst_rate = 37_894 / 100_000
    n_wst_holders = math.floor(n_accounts * wst_rate)

    redeem_rate = 0.25
    n_redeemers = math.floor((n_accounts - n_wst_holders) * redeem_rate)

    # Initial setup. Deposit
    distribute_initial_tokens(vKSM, lido, accounts)
    initial_xc_ksm_balances = []

    for acc in accounts:
        initial_xc_ksm_balances.append(vKSM.balanceOf(acc))

    deposit_amount = 20 * 10**12

    for i, acc in enumerate(accounts):
        if (i < n_wst_holders):
            vKSM.approve(wstKSM, deposit_amount, {"from": acc})
            wstKSM.submit(deposit_amount, {"from": acc})
        else:
            lido.deposit(deposit_amount, {"from": acc})

    # Wait for 2 eras to bond funds
    for _ in range(2):
        relay.new_era()

    assert relay.ledgers[0].active_balance > 0
    assert relay.ledgers[1].active_balance > 0
    assert relay.ledgers[2].active_balance > 0

    # Initial setup. Redeem
    for i in range(n_wst_holders, n_wst_holders + n_redeemers):
        acc = accounts[i]
        st_ksm_balance = lido.balanceOf(acc)
        lido.redeem(st_ksm_balance // 2, {"from": acc})

    ########################
    # Test setup completed #
    ########################

    # Start forced unbond process

    # Step 1. Disable deposits
    lido.setDepositCap(1, {"from": accounts[0]})

    # Confirm that deposits are disabled
    with brownie.reverts("LIDO: DEPOSITS_EXCEED_CAP"):
        lido.deposit(deposit_amount, {"from": accounts[0]})

    # Step 2. Chill all ledgers
    for _ledger in relay.ledgers:
        ledger = Ledger.at(_ledger.ledger_address)
        tx = ledger.chill({"from": accounts[0]})
        relay._after_report(tx)
    relay.new_era()

    for _ledger in relay.ledgers:
        assert _ledger.status == "Chill"

    # Update Lido contract implementation
    owner = proxy_admin.owner()
    lido_unbond = LidoUnbond.deploy({"from": accounts[0]})
    proxy_admin.upgrade(lido, lido_unbond, {"from": owner})
    Lido.remove(lido)
    lido = LidoUnbond.at(lido)

    for i in range(n_wst_holders, n_wst_holders + n_redeemers):
        acc = accounts[i]
        st_ksm_balance = lido.balanceOf(acc)
        lido.redeem(st_ksm_balance, {"from": acc})

    relay.new_era([3.141592 * 10 ** 12] * len(relay.ledgers))

    # Step 3. Disable redeems
    lido.setIsRedeemDisabled(True, {"from": accounts[0]})

    # Confirm that redeems are disabled
    with brownie.reverts("LIDO: REDEEM_DISABLED"):
        st_ksm_balance = lido.balanceOf(accounts[0])
        lido.redeem(st_ksm_balance, {"from": accounts[0]})

    # Step 4. Pause for 1 week
    n_eras_in_week = 28
    for _ in range(n_eras_in_week):
        relay.new_era()

    # Step 5. Set bufferedRedeems to the value of fundRaisedBalance
    lido.setBufferedRedeems(lido.fundRaisedBalance(), {"from": owner})

    # Step 6. Set isForcedUnbond to True
    lido.setIsUnbondForced(True, {"from": owner})

    # Trigger new era for bufferedRedeems = fundRaisedBalance to take effect
    # also invoke losses
    relay.new_era([-3.141592 * 10 ** 12] * len(relay.ledgers))

    # Make sure that forced unbond has started
    assert lido.ledgerStake(relay.ledgers[0].ledger_address) == 0
    assert lido.ledgerStake(relay.ledgers[1].ledger_address) == 0
    assert lido.ledgerStake(relay.ledgers[2].ledger_address) == 0

    # Step 7. Confirm that wrap / unwrap works correctly for wst token holders
    for i in range(n_wst_holders):
        acc = accounts[i]
        wst_balance = wstKSM.balanceOf(acc)
        unwrapped_st_ksm = wstKSM.unwrap(wst_balance, {"from": acc})
        assert lido.balanceOf(acc) == unwrapped_st_ksm.return_value

        lido.approve(wstKSM, unwrapped_st_ksm.return_value, {"from": acc})
        wst_balance_after = wstKSM.wrap(unwrapped_st_ksm.return_value, {"from": acc})
        assert wst_balance_after.return_value == wst_balance

    # Step 8. Claim manually unbonded funds
    for i in range(n_wst_holders, n_wst_holders + n_redeemers):
        acc = accounts[i]
        lido.claimUnbonded({"from": acc})
        assert vKSM.balanceOf(acc) == initial_xc_ksm_balances[i]

    # Step 9. Pause for 1 week
    for _ in range(n_eras_in_week):
        relay.new_era()

    # Step 10. Claim forcefully unbonded funds of stKSM holders
    for i in range(n_wst_holders + n_redeemers, n_accounts):
        acc = accounts[i]
        lido.claimForcefullyUnbonded({"from": acc})
        assert vKSM.balanceOf(acc) == initial_xc_ksm_balances[i]

    # Confirm that only wstKSM hodlers' funds are remaining in Lido
    assert lido.fundRaisedBalance() == n_wst_holders * deposit_amount

    # Step 11. Claim forcefully unbonded funds of wstKSM holders
    for i in range(n_wst_holders):
        acc = accounts[i]
        wst_ksm_to_unwrap = wstKSM.balanceOf(acc)
        wstKSM.unwrap(wst_ksm_to_unwrap, {"from": acc})
        lido.claimForcefullyUnbonded({"from": acc})
        assert vKSM.balanceOf(acc) == initial_xc_ksm_balances[i]

    # Step 12. Confirm that no funds remained in Lido
    assert lido.fundRaisedBalance() == 0