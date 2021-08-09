// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IvAccounts {
    function relayTransferFrom(bytes32 relayChainAccount, uint256 amount) external;
    function relayTransactCallAll(bytes32 relayChainAccount, bytes32 guarantor, uint256 feeCredit, bytes[] memory calls) external;
    function relayTransactCall(bytes32 relayChainAccount, bytes32 guarantor, uint256 feeCredit, bytes[] memory calls) external;
}
