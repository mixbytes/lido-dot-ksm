// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./ILido.sol";
interface ILidoOracle {
    event MemberAdded(address member);
    event MemberRemoved(address member);
    event QuorumChanged(uint8 quorum);

    enum StakeStatus{
        // bonded but not participate in staking
        Idle,
        // participate as nominator
        Nominator,
        // participate as validator
        Validator,
        // not bonded not participate in staking
        None,
        // marker. It's used for exclusion from staking
        Blocked
    }

    struct RelaySpec {
        uint64 genesisTimestamp;
        uint64 secondsPerEra;
    }

    struct UnlockingChunk {
        uint128 balance;
        uint64 era;
    }

    struct LedgerData {
        bytes32 stashAccount;
        bytes32 controllerAccount;
        StakeStatus stakeStatus;
        // active part of stash balance
        uint128 activeBalance;
        // locked for stake stash balance.
        uint128 totalBalance;
        // totalBalance = activeBalance + sum(unlocked.balance)
        UnlockingChunk[] unlocking;
        uint32[] claimedRewards;
        // stash account balance. It includes locked (totalBalance) balance assigned
        // to a controller.
        uint128 stashBalance;
    }



    /**
     * @notice Accept oracle committee member reports from the relay side
     * @param _eraId relay chain Era index
     * @param staking relay chain stash account balances and other properties
     */
    function reportRelay(uint64 _eraId, LedgerData calldata staking) external;

    function getStakeAccounts(address oracle) external view returns (ILido.Stash[] memory);

    function getCurrentEraId() external view returns (uint64);
}
