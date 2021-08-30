// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

interface XcmPrecompile {
    function sendUmp(bytes memory message) external;

    function relayTransferFrom(bytes32 relayChainAccount, uint256 amount) external;

    function relayTransferTo(bytes32 relayChainAccount, uint256 amount) external;

    function relayTransactCallAll(bytes32 relayChainAccount, bytes32 guarantor, uint256 feeCredit, bytes[] memory calls) external;

    function relayTransactCall(bytes32 relayChainAccount, bytes32 guarantor, uint256 feeCredit, bytes[] memory calls) external;

    function relayTransactRaw(bytes32 relayChainAccount, uint[] memory len, bytes memory calls) external;

    function relayProxy(bytes32 relayChainAccount, bytes calldata message) external;

    function buildBond(bytes32 controller, bytes32[] memory validators, uint256 amount) external view returns (bytes memory);

    function buildBondExtra(uint256 amount) external view returns (bytes memory);

    function buildUnBond(uint256 amount) external view returns (bytes memory);

    function buildReBond(uint256 amount) external view returns (bytes memory);

    function buildWithdraw() external view returns (bytes memory);

    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;
}
