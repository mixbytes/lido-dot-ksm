// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Types.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

interface ILido is IERC20 {
    function distributeRewards(uint128 _totalRewards) external;
    // Return oracle master address assigned to lido
    function getOracleMaster() external view returns (address);
    // Return the list of Polkadot/Kusama STASH accounts used for staking
    function getStashAccounts() external view returns (Types.Stash[] memory);
    function getLedgerAddresses() external view returns (address[] memory);
    function findLedger(bytes32 _stash) external view returns (address);

    function getMinStashBalance() external view returns (uint128);

    // Return average APY
    function getCurrentAPY() external view returns (uint256);
    // Deposit vKSM into Lido
    function deposit(uint256 amount) external;
    // Redeem LKSM in exchange for vKSM. Put LKSM in unbonding queue
    function redeem(uint256 amount) external;
    // Return the number of LKSM as (total LKSM awaiting unbonding period, available for claim )
    function getUnbonded(address holder) external returns (uint256);
    // Claim unbonded LKSM . Top up the caller vKSM balance burning LKSM
    function claimUnbonded() external;
}
