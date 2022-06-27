// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWithdrawal {
    // total virtual xcKSM amount on contract
    function totalVirtualXcKSMAmount() external returns (uint256);

    // Set stKSM contract address, allowed to only once
    function setStKSM(address _stKSM) external;

    // Returns total virtual xcKSM balance of contract for which losses can be applied
    function totalBalanceForLosses() external view returns (uint256);

    // Returns total xcKSM balance of contract which waiting for claim
    function pendingForClaiming() external view returns (uint256);

    // Burn pool shares from first element of queue and move index for allow claiming. After that add new batch
    function newEra() external;

    // Mint equal amount of pool shares for user. Adjust current amount of virtual xcKSM on Withdrawal contract.
    // Burn shares on LIDO side
    function redeem(address _from, uint256 _amount) external;

    // Returns available for claiming xcKSM amount for user
    function claim(address _holder) external returns (uint256);

    // Apply losses to current stKSM shares on this contract
    function ditributeLosses(uint256 _losses) external;

    // Check available for claim xcKSM balance for user
    function getRedeemStatus(address _holder) external view returns(uint256 _waiting, uint256 _available);
}