// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract RelayEncoder { // NOTE: this is logic for proxy contract

    // dev Encode 'bond' relay call
    // @param controller_address: Address of the controller
    // @param amount: The amount to bond
    // @param reward_destination: the account that should receive the reward
    // @returns The bytes associated with the encoded call
    function encode_bond(uint256 controller_address, uint256 amount, bytes memory reward_destination) external pure returns (bytes memory result) {
        return bytes.concat(hex"0600", hex"00", bytes32(controller_address), scaleCompactUint(amount), reward_destination);
    }

    // dev Encode 'bond_extra' relay call
    // @param amount: The extra amount to bond
    // @returns The bytes associated with the encoded call
    function encode_bond_extra(uint256 amount) external pure returns (bytes memory) {
        return bytes.concat(hex"0601", scaleCompactUint(amount));
    }

    // dev Encode 'unbond' relay call
    // @param amount: The amount to unbond
    // @returns The bytes associated with the encoded call
    function encode_unbond(uint256 amount) external pure returns (bytes memory) {
        return bytes.concat(hex"0602", scaleCompactUint(amount));
    }

    // dev Encode 'rebond' relay call
    // @param amount: The amount to rebond
    // @returns The bytes associated with the encoded call
    function encode_rebond(uint256 amount) external pure returns (bytes memory) {
        return bytes.concat(hex"0613", scaleCompactUint(amount));
    }

    // dev Encode 'withdraw_unbonded' relay call
    // @param slashes: Weight hint, number of slashing spans
    // @returns The bytes associated with the encoded call
    function encode_withdraw_unbonded(uint32 slashes) external pure returns (bytes memory) {
        if (slashes < 1<<8) {
            return bytes.concat(hex"0603", bytes1(uint8(slashes)), bytes3(0));
        }
        if(slashes < 1 << 16) {
            uint32 bt2 = slashes / 256;
            uint32 bt1 = slashes - bt2 * 256;
            return bytes.concat(hex"0603", bytes1(uint8(bt1)), bytes1(uint8(bt2)), bytes2(0));
        }
        if(slashes < 1 << 24) {
            uint32 bt3 = slashes / 65536;
            uint32 bt2 = (slashes - bt3 * 65536) / 256;
            uint32 bt1 = slashes - bt3 * 65536 - bt2 * 256;
            return bytes.concat(hex"0603", bytes1(uint8(bt1)), bytes1(uint8(bt2)), bytes1(uint8(bt3)), bytes1(0));
        }
        uint32 bt4 = slashes / 16777216;
        uint32 bt3 = (slashes - bt4 * 16777216) / 65536;
        uint32 bt2 = (slashes - bt4 * 16777216 - bt3 * 65536) / 256;
        uint32 bt1 = slashes - bt4 * 16777216 - bt3 * 65536 - bt2 * 256;
        return bytes.concat(hex"0603", bytes1(uint8(bt1)), bytes1(uint8(bt2)), bytes1(uint8(bt3)), bytes1(uint8(bt4)));
    }

    // dev Encode 'nominate' relay call
    // @param nominees: An array of AccountIds corresponding to the accounts we will nominate
    // @param blocked: Whether or not the validator is accepting more nominations
    // @returns The bytes associated with the encoded call
    function encode_nominate(uint256 [] memory nominees) external pure returns (bytes memory) {
        if (nominees.length == 0) {
            return hex"060500";
        }
        bytes memory result = bytes.concat(hex"0605", scaleCompactUint(nominees.length));
        for (uint256 i = 0; i < nominees.length; ++i) {
            result = bytes.concat(result, hex"00", bytes32(nominees[i]));
        }
        return result;
    }

    // dev Encode 'chill' relay call
    // @returns The bytes associated with the encoded call
    function encode_chill() external pure returns (bytes memory) {
        return hex"0606";
    }

    /**
    * @notice Converting uint256 value to le bytes
    * @param value - uint256 value
    * @param len - length of output bytes array
    */
    function toLeBytes(uint256 value, uint256 len) internal pure returns(bytes memory) {
        bytes memory out = new bytes(len);
        for (uint256 idx = 0; idx < len; ++idx) {
            out[idx] = bytes1(uint8(value));
            value = value >> 8;
        }
        return out;
    }

    /**
    * @notice Converting uint256 value to bytes
    * @param value - uint256 value
    */
    function scaleCompactUint(uint256 value) internal pure returns(bytes memory) {
        if (value < 1<<6) {
            return toLeBytes(value << 2, 1);
        }
        else if(value < 1 << 14) {
            return toLeBytes((value << 2) + 1, 2);
        }
        else if(value < 1 << 30) {
            return toLeBytes((value << 2) + 2, 4);
        }
        else {
            uint256 numBytes = 0;
            {
                uint256 m = value;
                for (; numBytes < 256 && m != 0; ++numBytes) {
                    m = m >> 8;
                }
            }

            bytes memory out = new bytes(numBytes + 1);
            out[0] = bytes1(uint8(((numBytes - 4) << 2) + 3));
            for (uint256 i = 0; i < numBytes; ++i) {
                out[i + 1] = bytes1(uint8(value & 0xFF));
                value = value >> 8;
            }
            return out;
        }
    }
}