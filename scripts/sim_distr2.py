import random
import numpy as np


class Lido:
    ledger_shares = []
    ledger_stakes = []

    total_stake = 0

    buffered_stakes = 0
    buffered_redeems = 0

    def __init__(self, ledgers_amount):
        self.ledger_stakes = [0] * ledgers_amount
        self.ledger_shares = [100] * ledgers_amount

    def set_shares(self, shares):
        assert len(self.ledger_shares) == len(shares)
        self.ledger_shares = shares

    def total_ledger_shares(self):
        return sum(self.ledger_shares)

    def target_stakes(self):
        arr = [0] * len(self.ledger_shares)
        total_shares = self.total_ledger_shares()

        return self._distr_prop(arr, self.total_stake, self.ledger_shares, total_shares)

    def stake(self, amount):
        self.buffered_stakes += amount
        self.total_stake += amount

        print("+++STAKE+++", amount)

    def redeem(self, amount):
        assert amount <= self.total_stake
        self.buffered_redeems += amount
        self.total_stake -= amount

        print("---REDEEM---", amount)

    def rewards(self, ledger_rewards):
        assert len(ledger_rewards) == len(self.ledger_stakes)
        for i in range(len(ledger_rewards)):
            assert self.ledger_stakes[i] + ledger_rewards[i] >= 0
            self.ledger_stakes[i] += ledger_rewards[i]
            self.total_stake += ledger_rewards[i]

        print("-+-REWARDS-+-  ", np.array(ledger_rewards))

    def soft_rebalance(self):
        self._uni_distr(self.buffered_stakes - self.buffered_redeems)
#        if self.buffered_stakes > self.buffered_redeems:
#            self._distr_stake(self.buffered_stakes - self.buffered_redeems)
#        elif self.buffered_stakes < self.buffered_redeems:
#            self._distr_unstake(self.buffered_redeems - self.buffered_stakes)

        self.buffered_stakes = 0
        self.buffered_redeems = 0

    def _distr_unstake(self, stake):
        diffs = []
        min_diff = 2**256
        pos_diffs_sum = 0
        neg_diffs_sum = 0
        for i in range(len(self.ledger_stakes)):
            target_stake = self.total_stake * self.ledger_shares[i] // self.total_ledger_shares()
            diff = target_stake - self.ledger_stakes[i]
            diffs.append(diff)
            if diff < 0:
                neg_diffs_sum += -diff
            else:
                pos_diffs_sum += diff

        assert(neg_diffs_sum > pos_diffs_sum)
        print('DIFFS error(-):', neg_diffs_sum - pos_diffs_sum + stake)

        total_decrement = 0
        for i in range(len(self.ledger_stakes)):
            if diffs[i] < 0:
                decrement = -diffs[i] * stake // neg_diffs_sum
                self.ledger_stakes[i] -= decrement
                total_decrement += decrement

        remaining = stake - total_decrement
        if remaining > 0:
            for i in range(len(self.ledger_stakes)):
                if self.ledger_stakes[i] > 0:
                    decrement = min(self.ledger_stakes[i], remaining)
                    self.ledger_stakes[i] -= decrement
                    remaining -= decrement
                    if remaining == 0:
                        break

    def _distr_stake(self, stake):
        diffs = []
        pos_diffs_sum = 0
        neg_diffs_sum = 0
        for i in range(len(self.ledger_stakes)):
            target_stake = self.total_stake * self.ledger_shares[i] // self.total_ledger_shares()
            diff = target_stake - self.ledger_stakes[i]
            diffs.append(diff)
            if diff < 0:
                neg_diffs_sum += -diff
            else:
                pos_diffs_sum += diff

        assert(pos_diffs_sum > neg_diffs_sum)
        print('DIFFS error(+):', pos_diffs_sum - neg_diffs_sum - stake)

        total_increment = 0
        for i in range(len(self.ledger_stakes)):
            if diffs[i] > 0 and self.ledger_shares[i] > 0:
                increment = diffs[i] * stake // pos_diffs_sum
                self.ledger_stakes[i] += increment
                total_increment += increment

        remaining = stake - total_increment
        if remaining > 0:
            for i in range(len(self.ledger_stakes)):
                if self.ledger_shares[i] > 0:
                    self.ledger_stakes[i] += remaining
                    break

    def _uni_distr(self, stake):
        diffs = []
        active_diffs_sum = 0
        for i in range(len(self.ledger_stakes)):
            target_stake = self.total_stake * self.ledger_shares[i] // self.total_ledger_shares()
            diff = target_stake - self.ledger_stakes[i]
            diffs.append(diff)
            if diff < 0 and stake < 0:
                active_diffs_sum += -diff
            elif diff > 0 and stake > 0:
                active_diffs_sum += diff

        total_change = 0

        if active_diffs_sum != 0:
            direction = 1
            if stake < 0:
                direction = -1

            for i in range(len(self.ledger_stakes)):
                if diffs[i] * direction > 0 and (direction < 0 or self.ledger_shares[i] > 0):
                    change = diffs[i] * stake // active_diffs_sum
                    self.ledger_stakes[i] += direction * change
                    total_change += direction * change

        remaining = stake - total_change
        print('stake, total_change:', stake, total_change)
        print('REMAINING:', remaining)
        if remaining > 0:
            for i in range(len(self.ledger_stakes)):
                if self.ledger_shares[i] > 0:
                    self.ledger_stakes[i] += remaining
                    break
        elif remaining < 0:
            for i in range(len(self.ledger_stakes)):
                if self.ledger_stakes[i] > 0:
                    decrement = min(self.ledger_stakes[i], -remaining)
                    self.ledger_stakes[i] -= decrement
                    remaining += decrement
                    if remaining == 0:
                        break


    def _diffs(self, from_arr, to_arr, reverse=False):
        assert len(from_arr) == len(to_arr)
        diffs = []
        for i in range(len(from_arr)):
            if not reverse:
                diffs.append(from_arr[i] - to_arr[i])
            else:
                diffs.append(to_arr[i] - from_arr[i])
        return diffs

    def _distr_prop(self, arr, amount, props, props_sum):
        non_zero_prop = -1
        chunks_sum = 0
        for i in range(len(props)):
            chunk = amount * props[i] // props_sum
            arr[i] += chunk
            chunks_sum += chunk

            if non_zero_prop < 0 and props[i] > 0:
                non_zero_prop = i

        dust = amount - chunks_sum
        if dust > 0 and non_zero_prop != -1:
            arr[non_zero_prop] += dust

        return arr

    def print(self):
        target_stakes = self.target_stakes()
        diffs = self._diffs(target_stakes, self.ledger_stakes)
        relative_diffs = []
        for i in range(len(self.ledger_stakes)):
            if target_stakes[i] > 0:
                relative_diffs.append(diffs[i] / target_stakes[i] * 100)
            else:
                relative_diffs.append(100)

        print('\n=======================================================================')
        print('Target stakes: ', np.array(target_stakes), "sum: ", sum(target_stakes))
        print('Real   stakes: ', np.array(self.ledger_stakes), "sum: ", sum(self.ledger_stakes))
        print('Diffs        : ', np.array(diffs))
        print('Rel. diffs%  : ', np.array(relative_diffs))
        print('=======================================================================\n')


np.set_printoptions(precision=3, formatter={'float': lambda x: f"{x:10.3f}", 'all': lambda x: f"{x:10d}"})

STAKE_MAX = 100000
REWARD_MAX = 1000

lido = Lido(5)
lido.stake(STAKE_MAX)
lido.soft_rebalance()
lido.print()

stake_sum = lido.total_stake
for i in range(100000000):
    prev_stakes = lido.ledger_stakes.copy()
    rewards = random.choices(range(max(-min(lido.ledger_stakes), -REWARD_MAX), REWARD_MAX), k=len(lido.ledger_stakes))
    lido.rewards(rewards)
    stake = random.randrange(max(-lido.total_stake, -STAKE_MAX), STAKE_MAX)
    if stake > 0:
        lido.stake(stake)
    else:
        lido.redeem(-stake)
    lido.soft_rebalance()
    lido.print()
    stake_sum += stake + sum(rewards)

    after_stakes = lido.ledger_stakes.copy()
    unbondings = 0
    bondings = 0
    for i in range(len(prev_stakes)):
        if after_stakes[i] < prev_stakes[i] + rewards[i]:
            unbondings += 1
        elif after_stakes[i] > prev_stakes[i] + rewards[i]:
            bondings += 1

    print('UNBONDINGS AMOUNT: ', unbondings)
    print('BONDINGS AMOUNT:   ', bondings, "\n\n")
    assert(not (stake > 0 and unbondings > 0))
    assert(not (stake < 0 and bondings > 0))
    assert(sum(lido.ledger_stakes) == sum(lido.target_stakes()))
    assert(sum(lido.ledger_stakes) == stake_sum)
