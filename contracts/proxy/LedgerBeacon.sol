// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../../interfaces/ILido.sol";
import "../../interfaces/IAuthManager.sol";

/**
 * @dev This contract is used in conjunction with one or more instances of {BeaconProxy} to determine their
 * implementation contract, which is where they will delegate all function calls.
 *
 * An ROLE_BEACON_MANAGER is able to change the implementation the beacon points to, thus upgrading the proxies that use this beacon.
 */
contract LedgerBeacon is IBeacon {
    // LIDO address
    address public LIDO;

    // current revision index
    uint256 public currentRevision;

    // index of newest revision
    uint256 public latestRevision;

    // array of implementations
    address[] public revisionImplementation;

    // revision index for specific ledger (if revision == 0 => current revision used)
    mapping(address => uint256) public ledgerRevision;

    // Beacon manager role
    bytes32 internal constant ROLE_BEACON_MANAGER = keccak256("ROLE_BEACON_MANAGER");

    /**
     * @dev Emitted when new implementation revision added.
     */
    event NewRevision(address indexed implementation);

    /**
     * @dev Emitted when current revision updated.
     */
    event NewCurrentRevision(address indexed implementation);

    modifier auth(bytes32 role) {
        require(IAuthManager(ILido(LIDO).AUTH_MANAGER()).has(role, msg.sender), "LEDGER_BEACON: UNAUTHOROZED");
        _;
    }

    /**
     * @dev Sets the address of the initial implementation, and the deployer account as the owner who can upgrade the
     * beacon.
     */
    constructor(address implementation_, address _lido) {
        _setImplementation(implementation_);
        currentRevision = latestRevision;
        LIDO = _lido;
    }

    /**
     * @dev Returns the current implementation address.
     */
    function implementation() public view virtual override returns (address) {
        if (ledgerRevision[msg.sender] != 0) {
            return revisionImplementation[ledgerRevision[msg.sender] - 1];
        }
        return revisionImplementation[currentRevision - 1];
    }

    /**
    * @dev Set ledger revision to `_revision`
    */
    function setLedgerRevision(address _ledger, uint256 _revision) external auth(ROLE_BEACON_MANAGER) {
        require(
            (ledgerRevision[_ledger] == 0 && _revision > 0 && _revision <= latestRevision) || 
            (ledgerRevision[_ledger] > 0 && _revision == 0), 
            "LEDGER_BEACON: INCORRECT_REVISION"
        );
        ledgerRevision[_ledger] = _revision;
    }

    /**
    * @dev Update current revision
    */
    function setCurrentRevision(uint256 _newCurrentRevision) external auth(ROLE_BEACON_MANAGER) {
        require(_newCurrentRevision > 0 && _newCurrentRevision <= latestRevision, "LEDGER_BEACON: INCORRECT_REVISION");
        currentRevision = _newCurrentRevision;
        emit NewCurrentRevision(revisionImplementation[_newCurrentRevision - 1]);
    }

    /**
     * @dev Add new revision of implementation to beacon.
     *
     * Emits an {Upgraded} event.
     *
     * Requirements:
     *
     * - msg.sender must be the owner of the contract.
     * - `newImplementation` must be a contract.
     */
    function addImplementation(address newImplementation) public auth(ROLE_BEACON_MANAGER) {
        _setImplementation(newImplementation);
        emit NewRevision(newImplementation);
    }

    /**
     * @dev Sets the implementation contract address for this beacon
     *
     * Requirements:
     *
     * - `newImplementation` must be a contract.
     */
    function _setImplementation(address newImplementation) private {
        require(Address.isContract(newImplementation), "LEDGER_BEACON: implementation is not a contract");
        latestRevision += 1;
        revisionImplementation.push(newImplementation);
    }
}