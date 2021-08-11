// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "zeppelin/token/ERC20/IERC20.sol";

interface IvKSM is IERC20 {
    function relayTransferTo(bytes32 relayChainAccount, uint256 amount) external;
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
}
