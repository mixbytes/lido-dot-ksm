// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IvKSM is IERC20 {
    function relayTransferTo(bytes32 relayChainAccount, uint256 amount) external;
}
