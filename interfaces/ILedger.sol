// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Types.sol";

interface ILedger {
    function initialize(
        bytes32 _stashAccount,
        bytes32 _controllerAccount,
        uint64 _startEraId,
        address _vKSM,
        address _AUX,
        address _vAccounts
    ) external;
    function pushData(uint64 _eraId, Types.OracleData calldata staking) external;
    
    function exactStake(uint128 _amount) external;
    function stake(uint128 _amount) external;
    function unstake(uint128 _amount) external;
    function nominate(bytes32[] calldata validators) external;

    function getStatus() external view returns (Types.LedgerStatus);
    function stashAccount() external view returns (bytes32);
    function controllerAccount() external view returns (bytes32);
}