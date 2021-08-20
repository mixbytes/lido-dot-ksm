// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./ILido.sol";
import "./ILedger.sol";
interface ILidoOracle {
    event MemberAdded(address member);
    event MemberRemoved(address member);
    event QuorumChanged(uint8 quorum);


    struct RelaySpec {
        uint64 genesisTimestamp;
        uint64 secondsPerEra;
    }


    /**
     * @notice Accept oracle committee member reports from the relay side
     * @param _eraId relay chain Era index
     * @param staking relay chain stash account balances and other properties
     */
    function reportRelay(uint64 _eraId, ILedger.LedgerData calldata staking) external;

    function getCurrentEraId() external view returns (uint64);

    function getStashAccounts() external view returns (ILido.Stash[] memory);
}
