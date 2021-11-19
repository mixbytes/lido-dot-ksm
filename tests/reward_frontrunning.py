from brownie import chain
from helpers import RelayChain, distribute_initial_tokens



def test_reward_frontrunning(lido, oracle_master, vKSM, accounts, developers, treasury):
    distribute_initial_tokens(vKSM, lido, accounts)

    relay = RelayChain(lido, vKSM, oracle_master, accounts, chain)
    relay.new_ledger("0x10", "0x11", 100)

    deposit1 = 20 * 10**18
    lido.deposit(deposit1, {'from': accounts[0]})

    relay.new_era()
    assert relay.ledgers[0].free_balance == deposit1
    assert relay.ledgers[0].active_balance == 0

    deposit2 = 5 * 10**18
    # Deposit right before report with reward for ledger
    lido.deposit(deposit2, {'from': accounts[1]})
    acc2_balance_before = lido.balanceOf(accounts[1])

    print('LIDO balance of user before: ' + str(acc2_balance_before / 10**18))

    reward = 3 * 10**18
    relay.new_era([reward])
    assert relay.ledgers[0].active_balance == deposit1 + reward
    assert lido.getTotalPooledKSM() == deposit1 + deposit2 + reward

    acc1_balance = lido.balanceOf(accounts[0])
    acc2_balance = lido.balanceOf(accounts[1])
    print('LIDO balance of user after: ' + str(acc2_balance / 10**18))
    print('user profit: ' + str((acc2_balance - acc2_balance_before) / 10**18))

    # redeem rewards (but if somebody add stKSM/vKSM pool in moonbeam MEV can use fl to increase profit)
    balance_for_redeem = lido.balanceOf(accounts[1])
    lido.redeem(balance_for_redeem, {'from': accounts[1]})

    balance_before_claim = vKSM.balanceOf(accounts[1])
    # move time forward to 28 epoches
    relay.timetravel(29)
    # Deposit to add some funds to redeem
    deposit3 = 10 * 10**18
    lido.deposit(deposit3, {'from': accounts[2]})

    lido.claimUnbonded({'from': accounts[1]})
    profit = acc2_balance - acc2_balance_before

    assert vKSM.balanceOf(accounts[1]) == balance_for_redeem + balance_before_claim
    assert profit > 0