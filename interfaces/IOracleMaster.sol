// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Types.sol";

interface IOracleMaster {
    /**
     * @notice Accept oracle committee member reports from the relay side
     * @param _eraId relay chain Era index
     * @param staking relay chain stash account balances and other properties
     */
    function reportRelay(uint64 _eraId, Types.OracleData calldata staking) external;

    function getCurrentEraId() external view returns (uint64);

    function getStashAccounts() external view returns (Types.Stash[] memory);

    function getQuorum() external view returns (uint256);

    function addLedger(address _ledger) external;

    function removeLedger(address _ledger) external;

    function getOracle(address _ledger) view external returns (address);

    function setRelayParams(uint64 _relayGenesisTs, uint64 _relaySecondsPerEra) external;
}