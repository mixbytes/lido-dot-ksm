// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./ILidoOracle.sol";
import "zeppelin/token/ERC20/IERC20.sol";

interface ILido is IERC20 {
    // Records a deposit made by a user
    event Submitted(address indexed sender, uint256 amount, address referral);
    // The `_amount` of KSM/(in the future DOT) was sent to the deposit function.
    event Unbuffered(uint256 amount);
    // Fee was updated
    event FeeSet(uint16 feeBasisPoints);


    function distributeRewards(uint128 _totalRewards) external;
    // Return oracle address assigned to lido
    function getOracle() external view returns (address);
    // Return the list of Polkadot/Kusama STASH accounts used for staking
    function getStashAccounts() external view returns (Stash[] memory);

    function clearReporting() external;
    function setQuorum(uint8 _quorum) external;
    function findLedger(bytes32 _stash) external view returns (address);
    function getMinStashBalance() external view returns (uint128);
    //function getBufferedBalance() external view returns (uint128);
    //function transferredBalance() external view returns (uint128);
    //function increaseBufferedBalance(uint128 amount, bytes32 _stashAccount) external;

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


    struct Stash {
        bytes32 stashAccount;
        uint64  eraId;
    }
}
