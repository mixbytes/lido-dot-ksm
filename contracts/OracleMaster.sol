// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/security/Pausable.sol";
import "@openzeppelin/proxy/Clones.sol";

import "../interfaces/IOracle.sol";
import "../interfaces/ILido.sol";
import "../interfaces/ILedger.sol";


contract OracleMaster is Pausable {
    using Clones for address;

    event MemberAdded(address member);
    event MemberRemoved(address member);
    event QuorumChanged(uint8 quorum);

    /// Maximum number of oracle committee members
    uint256 public constant MAX_MEMBERS = 255;
    // Missing member index
    uint256 internal constant MEMBER_NOT_FOUND = type(uint256).max;

    // Contract structured storage
    // Oracle members
    address[] private members;
    // Relaychain era timestamp
    Types.RelaySpec private relaySpec;

    // todo pack it with eraId as uint8
    uint8  public quorum;

    // Lido smart contract
    address private lido;

    mapping(address => address) private oracleForLedger;

    address  private member_manager;
    address  private quorum_manager;
    address  private spec_manager;

    address public oracleClone;

    // APY biases. low 16 bytes - slash (decrease) bias, high 16 bytes - reward (increase) bias
    uint256 private report_balance_bias;
    uint64 private eraId;


    modifier onlyLido() {
        require(msg.sender == lido, "CALLER_NOT_LIDO");
        _;
    }

    // todo remove.
    function _timestamp() external view returns (uint256){
        return block.timestamp;
    }

    function initialize(
        address _lido,
        address _member_manager,
        address _quorum_manager,
        address _spec_manager,
        address _oracleClone
    ) external {
        require(oracleClone == address(0), 'ALREADY_INITIALIZED');
        
        member_manager = _member_manager;
        quorum_manager = _quorum_manager;
        spec_manager = _spec_manager;

        lido = _lido;

        _setRelaySpec(0, 0);
        quorum = 1;
        oracleClone = _oracleClone;
    }

    /**
    *   @notice Stop pool routine operations
    */
    function pause() external auth(spec_manager) {
        _pause();
    }

    /**
    * @notice Resume pool routine operations
    */
    function resume() external auth(spec_manager) {
        _unpause();
    }

    modifier auth(address manager) {
        require(msg.sender == manager, "FORBIDDEN");
        _;
    }

    function setLido(address _lido) external auth(spec_manager) {
        lido = _lido;
    }

    function _getMemberId(address _member) internal view returns (uint256) {
        uint256 length = members.length;
        for (uint256 i = 0; i < length; ++i) {
            if (members[i] == _member) {
                return i;
            }
        }
        return MEMBER_NOT_FOUND;
    }

    /**
    * @notice Add `_member` to the oracle member committee list
    */
    function addOracleMember(address _member) external auth(member_manager) {
        require(address(0) != _member, "BAD_ARGUMENT");
        require(MEMBER_NOT_FOUND == _getMemberId(_member), "MEMBER_EXISTS");
        require(members.length < 254, "MEMBERS_TOO_MANY");

        members.push(_member);
        require(members.length < MAX_MEMBERS, "TOO_MANY_MEMBERS");
        emit MemberAdded(_member);
    }

    /**
    * @notice Remove '_member` from the oracle member committee list
    */
    function removeOracleMember(address _member) external auth(member_manager) {
        uint256 index = _getMemberId(_member);
        require(index != MEMBER_NOT_FOUND, "MEMBER_NOT_FOUND");
        uint256 last = members.length - 1;
        if (index != last) members[index] = members[last];
        members.pop();
        emit MemberRemoved(_member);

        // delete the data for the last epoch, let remained oracles report it again
        _clearReporting();
    }

    function _clearReporting() internal {
        address[] memory ledgers = ILido(lido).getLedgerAddresses();
        for (uint256 i = 0; i < ledgers.length; ++i) {
            address oracle = oracleForLedger[ledgers[i]];
            if (oracle != address(0)) {
                IOracle(oracle).cleanReporting();
            }
        }
    }

    function _setRelaySpec(
        uint64 _genesisTimestamp,
        uint64 _secondsPerEra
    ) private {
        Types.RelaySpec memory _relaySpec;
        _relaySpec.genesisTimestamp = _genesisTimestamp;
        _relaySpec.secondsPerEra = _secondsPerEra;

        relaySpec = _relaySpec;

        // todo emit event
    }

    function setRelaySpec(uint64 _genesisTimestamp, uint64 _secondsPerEra) external auth(spec_manager) {
        require(_genesisTimestamp > 0, "BAD_GENESIS_TIMESTAMP");
        require(_secondsPerEra > 0, "BAD_SECONDS_PER_ERA");

        _setRelaySpec(_genesisTimestamp, _secondsPerEra);
    }

    /**
    * @notice Set the number of exactly the same reports needed to finalize the epoch to `_quorum`
    */
    function setQuorum(uint8 _quorum) external auth(quorum_manager) {
        require(0 != _quorum, "QUORUM_WONT_BE_MADE");
        uint8 oldQuorum = quorum;
        quorum = _quorum;

        // If the quorum value lowered, check existing reports whether it is time to push
        if (oldQuorum > _quorum) {
            address[] memory ledgers = ILido(lido).getLedgerAddresses();
            for (uint256 i = 0; i < ledgers.length; ++i) {
                address oracle = oracleForLedger[ledgers[i]];
                if (oracle != address(0)) {
                    IOracle(oracle).softenQuorum(_quorum, eraId);
                }
            }
        }
        emit QuorumChanged(_quorum);
    }

    function addLedger(address _ledger) external onlyLido {
        IOracle newOracle = IOracle(oracleClone.cloneDeterministic(bytes32(uint256(uint160(_ledger)) << 96)));
        newOracle.initialize(address(this), _ledger);
        oracleForLedger[_ledger] = address(newOracle);
    }

    function removeLedger(address _ledger) external onlyLido {
        oracleForLedger[_ledger] = address(0);
    }

    function getOracle(address _ledger) view external returns (address) {
        return oracleForLedger[_ledger];
    }

    function getCurrentEraId() public view returns (uint64){
        return (uint64(block.timestamp) - relaySpec.genesisTimestamp ) / relaySpec.secondsPerEra;
    }

    /**
     * @notice Accept oracle committee member reports from the relay side
     * @param _eraId Relaychain era
     * @param report Relaychain report
     */
    function reportRelay(uint64 _eraId, Types.OracleData calldata report) external whenNotPaused {
        require(
            report.unlocking.length < type(uint8).max
            && report.totalBalance >= report.activeBalance
            && report.stashBalance >= report.totalBalance,
            'INCORRECT_REPORT'
        );

        address ledger = ILido(lido).findLedger(report.stashAccount);
        address oracle = oracleForLedger[ledger];
        require(oracle != address(0), 'ORACLE_FOR_LEDGER_NOT_FOUND');

        //TODO !!!!! fix condition !!!!!
        //require(_eraId == _getCurrentEraId(relaySpec), "UNEXPECTED_ERA");

        uint256 index = _getMemberId(msg.sender);
        require(index != MEMBER_NOT_FOUND, "MEMBER_NOT_FOUND");

        require(report.controllerAccount == ILedger(ledger).controllerAccount(), 'UNKNOWN_CONTROLLER');

        IOracle(oracle).reportRelay(index, quorum, _eraId, report);
        eraId = _eraId;
    }

    function getStashAccounts() external view returns (Types.Stash[] memory) {
        return ILido(lido).getStashAccounts();
    }
}
