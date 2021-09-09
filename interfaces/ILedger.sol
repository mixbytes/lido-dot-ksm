// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Types.sol";

interface ILedger {
    function initialize(
        bytes32 _stashAccount,
        bytes32 _controllerAccount,
        address _vKSM,
        address _AUX,
        address _vAccounts,
        uint128 _minNominatorBalance
    ) external;
    function pushData(uint64 _eraId, Types.OracleData calldata staking) external;

    function nominate(bytes32[] calldata validators) external;

    function status() external view returns (Types.LedgerStatus);
    function stashAccount() external view returns (bytes32);
    function totalBalance() external view returns (uint128);
}