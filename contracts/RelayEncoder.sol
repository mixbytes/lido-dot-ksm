// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IRelayEncoder.sol";
import "./utils/Encoding.sol";

contract RelayEncoder is IRelayEncoder {
    using Encoding for uint256;

    // first chain specific byte
    bytes public chain;

    /**
     * @dev Sets the chain first byte
     */
    constructor(bytes memory _chain) {
        // NOTE: for kusama first byte is 06, for polkadot first byte is 07
        chain = _chain;
    }

    // dev Encode 'bond' relay call
    // @param controller_address: Address of the controller
    // @param amount: The amount to bond
    // @param reward_destination: the account that should receive the reward
    // @returns The bytes associated with the encoded call
    function encode_bond(
        uint256 controller_address, 
        uint256 amount, 
        bytes memory reward_destination
    ) external override view returns (bytes memory result) {
        return bytes.concat(chain, hex"0000", bytes32(controller_address), amount.scaleCompactUint(), reward_destination);
    }

    // dev Encode 'bond_extra' relay call
    // @param amount: The extra amount to bond
    // @returns The bytes associated with the encoded call
    function encode_bond_extra(uint256 amount) external override view returns (bytes memory) {
        return bytes.concat(chain, hex"01", amount.scaleCompactUint());
    }

    // dev Encode 'unbond' relay call
    // @param amount: The amount to unbond
    // @returns The bytes associated with the encoded call
    function encode_unbond(uint256 amount) external override view returns (bytes memory) {
        return bytes.concat(chain, hex"02", amount.scaleCompactUint());
    }

    // dev Encode 'rebond' relay call
    // @param amount: The amount to rebond
    // @returns The bytes associated with the encoded call
    function encode_rebond(uint256 amount) external override view returns (bytes memory) {
        return bytes.concat(chain, hex"13", amount.scaleCompactUint());
    }

    // dev Encode 'withdraw_unbonded' relay call
    // @param slashes: Weight hint, number of slashing spans
    // @returns The bytes associated with the encoded call
    function encode_withdraw_unbonded(uint32 slashes) external override view returns (bytes memory) {
        if (slashes < 1<<8) {
            return bytes.concat(chain, hex"03", bytes1(uint8(slashes)), bytes3(0));
        }
        if(slashes < 1 << 16) {
            uint32 bt2 = slashes / 256;
            uint32 bt1 = slashes - bt2 * 256;
            return bytes.concat(chain, hex"03", bytes1(uint8(bt1)), bytes1(uint8(bt2)), bytes2(0));
        }
        if(slashes < 1 << 24) {
            uint32 bt3 = slashes / 65536;
            uint32 bt2 = (slashes - bt3 * 65536) / 256;
            uint32 bt1 = slashes - bt3 * 65536 - bt2 * 256;
            return bytes.concat(chain, hex"03", bytes1(uint8(bt1)), bytes1(uint8(bt2)), bytes1(uint8(bt3)), bytes1(0));
        }
        uint32 bt4 = slashes / 16777216;
        uint32 bt3 = (slashes - bt4 * 16777216) / 65536;
        uint32 bt2 = (slashes - bt4 * 16777216 - bt3 * 65536) / 256;
        uint32 bt1 = slashes - bt4 * 16777216 - bt3 * 65536 - bt2 * 256;
        return bytes.concat(chain, hex"03", bytes1(uint8(bt1)), bytes1(uint8(bt2)), bytes1(uint8(bt3)), bytes1(uint8(bt4)));
    }

    // dev Encode 'nominate' relay call
    // @param nominees: An array of AccountIds corresponding to the accounts we will nominate
    // @param blocked: Whether or not the validator is accepting more nominations
    // @returns The bytes associated with the encoded call
    function encode_nominate(uint256 [] memory nominees) external override view returns (bytes memory) {
        if (nominees.length == 0) {
            return bytes.concat(chain, hex"0500");
        }
        bytes memory result = bytes.concat(chain, hex"05", nominees.length.scaleCompactUint());
        for (uint256 i = 0; i < nominees.length; ++i) {
            result = bytes.concat(result, hex"00", bytes32(nominees[i]));
        }
        return result;
    }

    // dev Encode 'chill' relay call
    // @returns The bytes associated with the encoded call
    function encode_chill() external override view returns (bytes memory) {
        return bytes.concat(chain, hex"06");
    }
}