// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Types.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

interface ILido {
    function distributeRewards(uint128 _totalRewards) external;

    function getStashAccounts() external view returns (Types.Stash[] memory);

    function getLedgerAddresses() external view returns (address[] memory);

    function findLedger(bytes32 _stash) external view returns (address);

    function AUTH_MANAGER() external returns(address);

    function ORACLE_MASTER() external view returns (address);
}
