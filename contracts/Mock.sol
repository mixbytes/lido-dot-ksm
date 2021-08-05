// SPDX-License-Identifier: MIT
pragma solidity ^0.7.5;

pragma abicoder v2;

import "../interfaces/ILidoOracle.sol";
import "../interfaces/ILido.sol";
import "../interfaces/IRole.sol";


contract LidoMock is ILido {
    uint256 private _totalStake;
    address private owner;
    uint64  private eraId;


    event NewStake(uint256);

    constructor() public {
        owner = msg.sender;
        eraId = 0;
    }

    function reportRelay(uint64 _eraId, ILidoOracle.StakeReport memory staking) override external {
        uint256 total = 0;
        for (uint i = 0; i < staking.stake_ledger.length; i++) {
            total += staking.stake_ledger[i].stash_balance;
        }
        _totalStake = total;
        eraId = _eraId;
        emit NewStake(total);
    }

    function totalSupply() override external view returns (uint256) {
        return _totalStake;
    }

    function amendStake(uint256 total) external {
        _totalStake = total;
        emit NewStake(total);
    }
}

contract DummyRole is IRole {
    function has(bytes32 role, address member) external override view returns (bool){
        return true;
    }

    function add(bytes32 role, address member) external override {
        revert("NOT_IMPLEMENTED");
    }

    function remove(bytes32 role, address member) external override {
        revert("NOT_IMPLEMENTED");
    }
}

contract MockRole is IRole {
    address private owner;
    constructor() {
        owner = msg.sender;
    }
    function has(bytes32 role, address member) external override view returns (bool){
        return member == owner;
    }

    function add(bytes32 role, address member) external override {
        revert("NOT_IMPLEMENTED");
    }

    function remove(bytes32 role, address member) external override {
        revert("NOT_IMPLEMENTED");
    }
}


