// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "../../interfaces/IvAccounts.sol";
import "./vKSM_mock.sol";

contract vAccounts_mock is IvAccounts {
    event DownwardTransfer (
        bytes32 from,
        address to,
        uint256 amount
    );

    event RelayCallAll (
        bytes32 relayChainAccount, 
        bytes32 guarantor, 
        uint256 feeCredit, 
        bytes[] calls
    );

    event RelayCall (
        bytes32 relayChainAccount,
        bytes32 guarantor,
        uint256 feeCredit,
        bytes[] calls
    );


    vKSM_mock private vKSM;

    constructor(address _vKSM) {
        vKSM = vKSM_mock(_vKSM);
    }

    function relayTransferFrom(bytes32 relayChainAccount, uint256 amount) override external {
        emit DownwardTransfer(relayChainAccount, msg.sender, amount);
    }

    function relayTransactCallAll(bytes32 relayChainAccount, bytes32 guarantor, uint256 feeCredit, bytes[] memory calls) override external {
        emit RelayCallAll(relayChainAccount, guarantor, feeCredit, calls);
    }

    function relayTransactCall(bytes32 relayChainAccount, bytes32 guarantor, uint256 feeCredit, bytes[] memory calls) override external {
        emit RelayCall(relayChainAccount, guarantor, feeCredit, calls);
    }
}

