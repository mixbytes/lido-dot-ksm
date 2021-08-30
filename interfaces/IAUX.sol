// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IAUX {
    function buildBond(bytes32 controller, uint256 amount) external  returns (bytes memory);
    function buildBondExtra(uint256 amount) external  returns (bytes memory);
    function buildUnBond(uint256 amount) external  returns (bytes memory);
    function buildReBond(uint256 amount) external  returns (bytes memory);
    function buildWithdraw() external  returns (bytes memory);
    function buildNominate(bytes32[] memory validators) external  returns (bytes memory);
    function buildChill() external  returns (bytes memory);
}
