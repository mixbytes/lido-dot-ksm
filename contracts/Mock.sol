// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "../interfaces/ILidoOracle.sol";
import "../interfaces/ILido.sol";
import "zeppelin/token/ERC20/ERC20.sol";

contract LidoMock is ILido, ERC20 {
    address private owner;
    uint64  private eraId;

    event NewStake(uint64, uint256);

    constructor() ERC20("KSM liquid token", "LKSM") {
        owner = msg.sender;
        eraId = 0;
    }

    function getStakeAccounts(uint64 _eraId) override public view returns(bytes32[] memory){
        bytes32[] memory stake = new bytes32[](2);
        // Ferdie DE14BzQ1bDXWPKeLoAqdLAm1GpyAWaWF1knF74cEZeomTBM
        stake[0] = 0x1cbd2d43530a44705ad088af313e18f80b53ef16b36177cd4b77b846f2a5f07c;
        // Charlie Fr4NzY1udSFFLzb2R3qxVQkwz9cZraWkyfH4h3mVVk7BK7P
        stake[1] = 0x90b5ab205c6974c9ea841be688864633dc9ca8a357843eeacf2314649965fe22;
        return stake;
    }

    function deposit(uint256 amount) external override{
        revert("NOT_IMPLEMENTED");
    }

    function redeem(uint256 amount) external override{
        revert("NOT_IMPLEMENTED");
    }

    function getUnbonded() external override returns (uint256,uint256){
        revert("NOT_IMPLEMENTED");
    }

    function claimUnbonded() external override{
        revert("NOT_IMPLEMENTED");
    }

    function getCurrentAPY() external override view returns (uint256){
        return 540;
    }

    function setQuorum(uint256 _quorum) external override {
        revert("NOT_IMPLEMENTED");
    }

    function clearReporting() external override {
        revert("NOT_IMPLEMENTED");
    }

    function findLedger(bytes32 _stashAccount) external view override returns (address){
        revert("NOT_IMPLEMENTED");
    }

    function getOracle() external view override returns (address){
        return address(0);
    }
}

