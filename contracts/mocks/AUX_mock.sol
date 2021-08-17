// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "../../interfaces/IAUX.sol";

contract AUX_mock is IAUX {
    event Bond (
        bytes32 controller,
        bytes32[] validators,
        uint256 amount
    );

    event BondExtra (
        uint256 amount
    );

    event Unbond (
        uint256 amount
    );

    event Rebond (
        uint256 amount
    );

    event Withdraw (
    );

    event Nominate (
        bytes32[] validators
    );

    event Chill (
    );

    function buildBond(bytes32 controller, bytes32[] memory validators, uint256 amount) override external returns (bytes memory) {
        emit Bond(controller, validators, amount);
        return toBytes(0x00);
    }

    function buildBondExtra(uint256 amount) override external returns (bytes memory) {
        emit BondExtra(amount);
        return toBytes(0x01);
    }

    function buildUnBond(uint256 amount) override external returns (bytes memory) {
        emit Unbond(amount);
        return toBytes(0x02);
    }

    function buildReBond(uint256 amount) override external returns (bytes memory) {
        emit Rebond(amount);
        return toBytes(0x03);
    }

    function buildWithdraw() override external returns (bytes memory) {
        emit Withdraw();
        return toBytes(0x04);
    }

    function buildNominate(bytes32[] memory validators) override external returns (bytes memory) {
        emit Nominate(validators);
        return toBytes(0x05);
    }

    function buildChill() override external returns (bytes memory) {
        emit Chill();
        return toBytes(0x06);
    }

    function toBytes(bytes1 b) internal returns (bytes memory) {
        bytes memory bts = new bytes(1);
        bts[0] = b;
        return bts;
    }
}
