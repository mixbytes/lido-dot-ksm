// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Types.sol";

interface ILedger {
    function initialize(
        bytes32 _stashAccount,
        bytes32 controllerAccount,
        address vKSM,
        address controller,
        uint128 minNominatorBalance,
        address lido,
        uint128 _minimumBalance
    ) external;

    function pushData(uint64 eraId, Types.OracleData calldata staking) external;

    function nominate(bytes32[] calldata validators) external;

    function status() external view returns (Types.LedgerStatus);

    function isEmpty() external view returns (bool);

    function stashAccount() external view returns (bytes32);

    function totalBalance() external view returns (uint128);

    function setRelaySpecs(uint128 minNominatorBalance, uint128 minimumBalance) external;

    function cachedTotalBalance() external view returns (uint128);
}
