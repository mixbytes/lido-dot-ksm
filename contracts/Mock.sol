// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "../interfaces/ILidoOracle.sol";
import "../interfaces/ILido.sol";
import "zeppelin/token/ERC20/ERC20.sol";

contract LidoMock is ILido, ERC20 {
    address private owner;

    event NewStake(uint64, uint256);

    constructor() ERC20("KSM liquid token", "LKSM") {
        owner = msg.sender;
    }

    modifier notImplemented(){
        revert("NOT_IMPLEMENTED");
        _;
    }

    function getStakeAccounts(uint64 _eraId) override public view returns(bytes32[] memory){
        bytes32[] memory stake = new bytes32[](2);
        // Ferdie DE14BzQ1bDXWPKeLoAqdLAm1GpyAWaWF1knF74cEZeomTBM
        stake[0] = 0x1cbd2d43530a44705ad088af313e18f80b53ef16b36177cd4b77b846f2a5f07c;
        // Charlie Fr4NzY1udSFFLzb2R3qxVQkwz9cZraWkyfH4h3mVVk7BK7P
        stake[1] = 0x90b5ab205c6974c9ea841be688864633dc9ca8a357843eeacf2314649965fe22;
        return stake;
    }

    function deposit(uint256 amount) external override notImplemented{

    }

    function redeem(uint256 amount) external override notImplemented{

    }

    function getUnbonded() external override notImplemented returns (uint256,uint256) {

    }

    function claimUnbonded() external override notImplemented{

    }

    function getCurrentAPY() external override view returns (uint256){
        return 540;
    }

    function setQuorum(uint8 _quorum) external override notImplemented{

    }

    function clearReporting() external override notImplemented{

    }

    function findLedger(bytes32 _stashAccount) external view override notImplemented returns (address){

    }

    function getMinStashBalance() external view override returns (uint128){
        return 0;
    }

    function getOracle() external view override returns (address){
        return address(0);
    }

    function distributeRewards(uint128 _totalRewards, bytes32 _stashAccount) external override {
        _mint(address(this), _totalRewards);
    }

    function getBufferedBalance() external view override returns (uint128){
        return 0;
    }

    function transferredBalance() external view override returns (uint128){
        return 0;
    }

    function increaseBufferedBalance(uint128 amount, bytes32 _stashAccount) external override notImplemented{

    }
}
