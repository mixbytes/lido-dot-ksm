// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface ILedgerFactory {
    function createLedger(
        bytes32 _stashAccount,
        bytes32 _controllerAccount,
        address _vKSM,
        address _controller,
        uint128 _minNominatorBalance,
        uint128 _minimumBalance
    ) external returns (address);
}