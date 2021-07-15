// SPDX-License-Identifier: MIT
pragma solidity ^0.7.5;

pragma abicoder v2;

import "./ILidoOracle.sol";

interface ILido {
    function reportRelay(uint64 _eraId, ILidoOracle.StakeReport memory staking) external;

    function totalSupply() external returns (uint256);
}
