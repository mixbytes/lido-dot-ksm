// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "../../interfaces/IAUX.sol";

contract AUX_mock is IAUX {
    event Bond (
        address caller,
        bytes32 controller,
        uint256 amount
    );

    event BondExtra (
        address caller,
        uint256 amount
    );

    event Unbond (
        address caller,
        uint256 amount
    );

    event Rebond (
        address caller,
        uint256 amount
    );

    event Withdraw (
        address caller
    );

    event Nominate (
        address caller,
        bytes32[] validators
    );

    event Chill (
        address caller
    );

    function buildBond(bytes32 controller, uint256 amount) override external returns (bytes memory) {
        emit Bond(msg.sender, controller, amount);
        return toBytes(0x00);
    }

    function buildBondExtra(uint256 amount) override external returns (bytes memory) {
        emit BondExtra(msg.sender, amount);
        return toBytes(0x01);
    }

    function buildUnBond(uint256 amount) override external returns (bytes memory) {
        emit Unbond(msg.sender, amount);
        return toBytes(0x02);
    }

    function buildReBond(uint256 amount) override external returns (bytes memory) {
        emit Rebond(msg.sender, amount);
        return toBytes(0x03);
    }

    function buildWithdraw() override external returns (bytes memory) {
        emit Withdraw(msg.sender);
        return toBytes(0x04);
    }

    function buildNominate(bytes32[] memory validators) override external returns (bytes memory) {
        emit Nominate(msg.sender, validators);
        return toBytes(0x05);
    }

    function buildChill() override external returns (bytes memory) {
        emit Chill(msg.sender);
        return toBytes(0x06);
    }

    function toBytes(bytes1 b) internal returns (bytes memory) {
        bytes memory bts = new bytes(1);
        bts[0] = b;
        return bts;
    }
}
