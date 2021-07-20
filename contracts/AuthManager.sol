// SPDX-License-Identifier: MIT
pragma solidity ^0.7.5;

import "../interfaces/IRole.sol";


contract AuthManager is IRole {
    IRole private owner;
    address[] private members;
    uint256 internal constant NOTFOUND = uint256(-1);

    event AddMember(address);
    event RemoveMember(address);

    constructor(address superior) public {
        if (superior == address(0)) {
            owner = IRole(address(this));
            members.push(msg.sender);
        } else {
            owner = IRole(superior);
        }
    }

    function has(address _member) external override view returns (bool){
        return _find(_member) != NOTFOUND;
    }

    function _find(address _member) internal view returns (uint256){
        for (uint256 i = 0; i < members.length; ++i) {
            if (members[i] == _member) {
                return i;
            }
        }
        return NOTFOUND;
    }

    function add(address member) external override {
        require(owner.has(msg.sender), "FORBIDDEN");
        require(_find(member) == NOTFOUND, "ALREADY_MEMBER");
        members.push(member);
        emit AddMember(member);
    }

    function remove(address member) external override {
        require(owner.has(msg.sender), "FORBIDDEN");
        uint256 i = _find(member);
        require(i != NOTFOUND, "MEMBER_NOT_FOUND");

        if (address(owner) == address(this)) {
            require(members.length > 1, "SELFLOCK_FORBIDDEN");
        }
        if (i != members.length - 1) {
            members[i] = members[members.length - 1];
        }
        members.pop();

        emit RemoveMember(member);
    }

}


