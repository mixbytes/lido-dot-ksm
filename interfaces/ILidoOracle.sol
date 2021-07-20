// SPDX-License-Identifier: MIT
pragma solidity ^0.7.5;

pragma abicoder v2;

interface ILidoOracle {
    event AllowedBeaconBalanceAnnualRelativeIncreaseSet(uint256 value);
    event AllowedBeaconBalanceRelativeDecreaseSet(uint256 value);
    event BeaconReportReceiverSet(address callback);
    event MemberAdded(address member);
    event MemberRemoved(address member);
    event QuorumChanged(uint256 quorum);
    event ExpectedEraIdUpdated(uint256 epochId);
    event PostTotalShares(
        uint256 postTotalPooledEther,
        uint256 preTotalPooledEther,
        uint256 timeElapsed,
        uint256 totalShares
    );

    event Completed(uint256);
    event ContractVersionSet(uint256 version);

    enum StakeStatus{
        Idle,
        Nominator,
        Validator
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
        bytes32 stash;
        bytes32 controller;
        StakeStatus stake_status;

        uint128 active_balance;
        uint128 total_balance;
        UnlockingChunk[] unlocking;
        uint32[] claimed_rewards;
        uint128 stash_balance;
    }

    /**
     * @notice oracle committee member report structure
     */
    struct StakeReport {
        // todo. remove in future.
        uint128 parachain_balance;

        Ledger[] stake_ledger;
    }

    /**
     * @notice Accept oracle committee member reports from the relay side
     * @param _eraId relay chain Era index
     * @param staking relay chain stash account balances and other properties
     */
    function reportRelay(uint64 _eraId, StakeReport calldata staking) external;
}
