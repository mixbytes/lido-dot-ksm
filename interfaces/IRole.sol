// SPDX-License-Identifier: MIT
pragma solidity ^0.7.5;

interface IRole {
    function has(address member) external view returns (bool);

    function add(address member) external;

    function remove(address member) external;
}
