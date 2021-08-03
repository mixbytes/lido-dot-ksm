// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

pragma abicoder v2;

import "./ILidoOracle.sol";

interface ILido {
    function reportRelay(uint64 _eraId, ILidoOracle.StakeReport memory staking) external;

    // Records a deposit made by a user
    event Submitted(address indexed sender, uint256 amount, address referral);

    // The `_amount` of KSM/(in the future DOT) was sent to the deposit function.
    event Unbuffered(uint256 amount);
    event FeeSet(uint16 feeBasisPoints);

    // Return the list of Polkadot/Kusama STASH accounts used for staking
    function getStakeAccounts(uint64 _eraId) external view returns(bytes32[] memory);

    function getCurrentAPY() external view returns (uint256);
    // deposit vKSM into Lido
    function deposit(uint256 amount) external;
    // redeem LKSM in exchange for vKSM
    function redeem(uint256 amount) external;
    // return the number of LKSM as (total LKSM awaiting unbonding period, available for claim )
    function getUnbonded() external returns (uint256, uint256);
    // claim unbonded LKSM . Top up the caller vKSM balance
    function claimUnbonded() external;
}
