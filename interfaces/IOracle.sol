// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Types.sol";

interface IOracle {
    function initialize(address _oracleMaster, address _ledger) external;

    function reportRelay(uint256 index, uint256 quorum, uint64 eraId, Types.OracleData calldata staking) external;

    function softenQuorum(uint8 quorum, uint64 _eraId) external;

    function cleanReporting() external;
}