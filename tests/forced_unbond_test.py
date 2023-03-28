import math
import brownie

from brownie import chain
from helpers import RelayChain, distribute_initial_tokens


def test_forced_unbond(
        lido,
        oracle_master,
        proxy_admin,
        withdrawal,
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

    precision = 10 ** lido.decimals()
    deposit_amount = 20 * precision
    reward_amount = math.pi * precision
    loss_rate = -0.1 / len(relay.ledgers)

    n_eras_to_unbond = 32
    n_eras_after_redeem_disable = 7

    err_wei = 15

    for i, acc in enumerate(accounts):
        if (i < n_wst_holders):
            vKSM.approve(wstKSM, deposit_amount, {"from": acc})
            wstKSM.submit(deposit_amount, {"from": acc})
        else:
            lido.deposit(deposit_amount, {"from": acc})

    # Wait for 2 eras to bond funds
    for _ in range(2):
        relay.new_era()

    for _ledger in relay.ledgers:
        assert _ledger.active_balance > 0

    # Initial setup. Redeem half of the balance
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

    # Step 3. Update Lido contract implementation
    owner = proxy_admin.owner()
    lido_unbond = LidoUnbond.deploy({"from": accounts[0]})
    proxy_admin.upgrade(lido, lido_unbond, {"from": owner})
    Lido.remove(lido)
    lido = LidoUnbond.at(lido)

    # Step 4. Redeem remaining funds
    for i in range(n_wst_holders, n_wst_holders + n_redeemers):
        acc = accounts[i]
        st_ksm_balance = lido.balanceOf(acc)
        lido.redeem(st_ksm_balance, {"from": acc})

    # Distribute rewards and calculate amount of rewards received by each account
    balance_before = list(map(lambda u: lido.balanceOf(u), accounts))
    for i in range(n_wst_holders):
        balance_before[i] = wstKSM.getStKSMByWstKSM(wstKSM.balanceOf(accounts[i]))

    relay.new_era([reward_amount] * len(relay.ledgers))

    balance_after = list(map(lambda u: lido.balanceOf(u), accounts))
    for i in range(n_wst_holders):
        balance_after[i] = wstKSM.getStKSMByWstKSM(wstKSM.balanceOf(accounts[i]))

    accrued_rewards = []
    for after, before in zip(balance_after, balance_before):
        accrued_rewards.append(after - before)

    # Step 5. Disable redeems
    lido.setIsRedeemDisabled(True, {"from": accounts[0]})

    # Confirm that redeems are disabled
    with brownie.reverts("LIDO: REDEEM_DISABLED"):
        st_ksm_balance = lido.balanceOf(accounts[0])
        lido.redeem(st_ksm_balance, {"from": accounts[0]})

    # Step 6. Wait 7 eras after disabling redeems
    n_eras_after_redeem_disable = 7
    for _ in range(n_eras_after_redeem_disable):
        relay.new_era()

    # Step 7. Set bufferedRedeems to the value of fundRaisedBalance
    lido.setBufferedRedeems(lido.fundRaisedBalance(), {"from": owner})

    # Step 8. Set isForcedUnbond to True
    lido.setIsUnbondForced(True, {"from": owner})

    # Trigger new era to start forced unbond
    relay.new_era()

    forced_unbond_era = relay.era

    # Make sure that forced unbond has started
    for _ledger in relay.ledgers:
        assert lido.ledgerStake(_ledger.ledger_address) == 0

    # Invoke losses after forced unbond has started
    # and calculate received losses for each account
    balance_before_loss = list(map(lambda u: lido.balanceOf(u), accounts))
    for i in range(n_wst_holders):
        balance_before_loss[i] = wstKSM.getStKSMByWstKSM(wstKSM.balanceOf(accounts[i]))

    # For users who are already unbonding funds, losses are applied to
    # unbonding chunks, therefore we calculate applied loss as a difference
    # between expected amount of unbonded funds on withdrawal contract
    expected_before_losses = list(map(
        lambda u: withdrawal.getRedeemStatus(u)[0],
        accounts[n_wst_holders : n_wst_holders + n_redeemers]
    ))

    loss_amount = loss_rate * lido.totalSupply()
    relay.new_era([loss_amount])
    loss_era = relay.era

    balance_after_loss = list(map(lambda u: lido.balanceOf(u), accounts))
    for i in range(n_wst_holders):
        balance_after_loss[i] = wstKSM.getStKSMByWstKSM(wstKSM.balanceOf(accounts[i]))

    expected_after_losses = list(map(
        lambda u: withdrawal.getRedeemStatus(u)[0],
        accounts[n_wst_holders : n_wst_holders + n_redeemers]
    ))

    received_losses = []
    for after, before in zip(balance_after_loss, balance_before_loss):
        received_losses.append(after - before)

    # We only expect losses to impact the diff because rewards
    # have been distributed after redeems
    expected_diffs = []
    for after, before in zip(expected_after_losses, expected_before_losses):
        expected_diffs.append(after - before)

    # Step 9. Confirm that wrap / unwrap works correctly for wst token holders
    for i in range(n_wst_holders):
        acc = accounts[i]
        wst_balance = wstKSM.balanceOf(acc)
        unwrapped_st_ksm = wstKSM.unwrap(wst_balance, {"from": acc})
        assert abs(lido.balanceOf(acc) - unwrapped_st_ksm.return_value) <= err_wei

        lido.approve(wstKSM, unwrapped_st_ksm.return_value, {"from": acc})
        wst_balance_after = wstKSM.wrap(unwrapped_st_ksm.return_value, {"from": acc})
        assert abs(wst_balance_after.return_value - wst_balance) <= err_wei

    # Make sure claimForcefullyUnbonded() is unavaliable yet
    with brownie.reverts("WITHDRAWAL: INSUFFICIENT_BALANCE"):
        for i in range(n_wst_holders + n_redeemers, n_accounts):
            acc = accounts[i]
            lido.claimForcefullyUnbonded({"from": acc})

    # Wait remaining eras for manually created unbonding chunks to mature
    while relay.era < loss_era + n_eras_to_unbond:
        relay.new_era()

    # Step 10. Claim manually unbonded funds
    k = 0;
    for i in range(n_wst_holders, n_wst_holders + n_redeemers):
        acc = accounts[i]
        lido.claimUnbonded({"from": acc})
        assert abs(vKSM.balanceOf(acc) - initial_xc_ksm_balances[i]
                   - expected_diffs[k]) <= err_wei
        k += 1

    # Step 11. Wait for forced unbonding chunks to mature
    while relay.era < forced_unbond_era + n_eras_to_unbond:
        relay.new_era()

    # Confirm that wrap / unwrap works correctly for wst token holders
    for i in range(n_wst_holders):
        acc = accounts[i]
        wst_balance = wstKSM.balanceOf(acc)
        unwrapped_st_ksm = wstKSM.unwrap(wst_balance, {"from": acc})
        assert abs(lido.balanceOf(acc) - unwrapped_st_ksm.return_value) <= err_wei

        lido.approve(wstKSM, unwrapped_st_ksm.return_value, {"from": acc})
        wst_balance_after = wstKSM.wrap(unwrapped_st_ksm.return_value, {"from": acc})
        assert abs(wst_balance_after.return_value - wst_balance) <= err_wei

    # Step 12. Claim forcefully unbonded funds of stKSM holders
    for i in range(n_wst_holders + n_redeemers, n_accounts):
        acc = accounts[i]
        lido.claimForcefullyUnbonded({"from": acc})
        assert abs(vKSM.balanceOf(acc) - initial_xc_ksm_balances[i]
                   - accrued_rewards[i] - received_losses[i]) <= err_wei

    # Confirm that only wstKSM hodlers' funds are remaining in Lido
    wst_holders_rewards = sum(accrued_rewards[:n_wst_holders])
    wst_holders_losses = sum(received_losses[:n_wst_holders])
    assert abs(lido.fundRaisedBalance() - n_wst_holders * deposit_amount
               - wst_holders_rewards - wst_holders_losses) <= err_wei

    # Step 13. Claim forcefully unbonded funds of wstKSM holders
    for i in range(n_wst_holders):
        acc = accounts[i]
        wst_ksm_to_unwrap = wstKSM.balanceOf(acc)
        wstKSM.unwrap(wst_ksm_to_unwrap, {"from": acc})
        lido.claimForcefullyUnbonded({"from": acc})
        assert abs(vKSM.balanceOf(acc) - initial_xc_ksm_balances[i]
                   - accrued_rewards[i] - received_losses[i]) <= err_wei

    # Step 14. Confirm that no funds remained in Lido
    assert lido.fundRaisedBalance() <= err_wei
