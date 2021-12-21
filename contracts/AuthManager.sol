// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../interfaces/IAuthManager.sol";


contract AuthManager is IAuthManager, Initializable {
    // mapping which contains roles for address
    mapping(address => bytes32[])  internal members;

    // constant for showing that element not found in array
    uint256 internal constant NOT_FOUND = type(uint256).max;

    // hash for SUPER role
    bytes32 public constant SUPER_ROLE = keccak256("SUPER_ROLE");

    // event emitted when new member for role added
    event AddMember(address member, bytes32 role);

    // event emitted when member removed from role
    event RemoveMember(address member, bytes32 role);

    /**
    * @notice Initialize contract after deploying
    * @param superior - address of member which granted with super role
    */
    function initialize(address superior) external initializer {
        if (superior == address(0)) {
            members[msg.sender] = [SUPER_ROLE];
            emit AddMember(msg.sender, SUPER_ROLE);
        } else {
            members[superior] = [SUPER_ROLE];
            emit AddMember(superior, SUPER_ROLE);
        }
    }

    /**
    * @notice Function returns roles array for member
    * @param _member - address of member
    */
    function roles(address _member) external view returns (bytes32[] memory) {
        return members[_member];
    }

    /**
    * @notice Check if member has a specific role
    * @param role - hash of role string
    * @param _member - address of member
    */
    function has(bytes32 role, address _member) external override view returns (bool) {
        return _find(members[_member], role) != NOT_FOUND;
    }

    /**
    * @notice Add new role for member. Only SUPER_ROLE can add new roles
    * @param role - hash of a role string
    * @param member - address of member
    */
    function add(bytes32 role, address member) external override {
        require(_find(members[msg.sender], SUPER_ROLE) != NOT_FOUND, "FORBIDDEN");

        bytes32[] storage _roles = members[member];

        require(_find(_roles, role) == NOT_FOUND, "ALREADY_MEMBER");
        _roles.push(role);
        emit AddMember(member, role);
    }

    /**
    * @notice Add new role for member by string. Only SUPER_ROLE can add new roles
    * @param roleString - role string
    * @param member - address of member
    */
    function addByString(string calldata roleString, address member) external {
        require(_find(members[msg.sender], SUPER_ROLE) != NOT_FOUND, "FORBIDDEN");

        bytes32[] storage _roles = members[member];
        bytes32 role = keccak256(bytes(roleString));

        require(_find(_roles, role) == NOT_FOUND, "ALREADY_MEMBER");
        _roles.push(role);
        emit AddMember(member, role);
    }

    /**
    * @notice Remove role from member. Only SUPER_ROLE can add new roles
    * @param role - hash of a role string
    * @param member - address of member
    */
    function remove(bytes32 role, address member) external override {
        require(_find(members[msg.sender], SUPER_ROLE) != NOT_FOUND, "FORBIDDEN");
        require(msg.sender != member || role != SUPER_ROLE, "INVALID");

        bytes32[] storage _roles = members[member];

        uint256 i = _find(_roles, role);
        require(i != NOT_FOUND, "MEMBER_NOT_FOUND");
        if (_roles.length == 1) {
            delete members[member];
        } else {
            if (i < _roles.length - 1) {
                _roles[i] = _roles[_roles.length - 1];
            }
            _roles.pop();
        }

        emit RemoveMember(member, role);
    }

    /**
    * @notice Search _role index in _roles array
    * @param _roles - array of roles hashes
    * @param _role - hash of role string
    */
    function _find(bytes32[] storage _roles, bytes32 _role) internal view returns (uint256) {
        for (uint256 i = 0; i < _roles.length; ++i) {
            if (_role == _roles[i]) {
                return i;
            }
        }
        return NOT_FOUND;
    }

}
