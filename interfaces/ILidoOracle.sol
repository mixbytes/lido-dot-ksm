// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

pragma abicoder v2;

interface ILidoOracle {
    event MemberAdded(address member);
    event MemberRemoved(address member);
    event QuorumChanged(uint256 quorum);
    event ExpectedEraIdUpdated(uint256 epochId);
    event Completed(uint256);

    enum StakeStatus{
        // bonded but not participate in staking
        Idle,
        // participate as nominator
        Nominator,
        // participate as validator
        Validator,
        // not bonded not participate in staking
        None,
        // marker for exclusion from staking
        Blocked
    }

    struct RelaySpec {
        uint64 genesisTimestamp;
        uint64 secondsPerEra;
    }

    struct UnlockingChunk {
        uint128 balance;
        uint32 era;
    }

    struct Ledger {
        bytes32 stashAccount;
        bytes32 controllerAccount;
        StakeStatus stakeStatus;

        uint128 activeBalance;
        uint128 totalBalance;
        UnlockingChunk[] unlocking;
        uint32[] claimedRewards;
        uint128 stashBalance;
    }

    /**
     * @notice oracle committee member report
     */
    struct StakeReport {
        // todo. remove in future.
        uint128 parachainBalance;

        Ledger[] stakeLedger;
    }

    /**
     * @notice Accept oracle committee member reports from the relay side
     * @param _eraId relay chain Era index
     * @param staking relay chain stash account balances and other properties
     */
    function reportRelay(uint64 _eraId, StakeReport calldata staking) external;
    function getStakeAccounts() external view returns(bytes32[] memory);
}
