// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

pragma abicoder v2;

import "../interfaces/ILidoOracle.sol";
import "../interfaces/ILido.sol";
import "../node_modules/@openzeppelin/contracts/security/Pausable.sol";

library ReportUtils {
    // last bytes used to count votes 
    uint256 constant internal COUNT_OUTMASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00;

    /// @notice Check if the given reports are different, not considering the counter of the first
    function isDifferent(uint256 value, uint256 that) internal pure returns (bool) {
        return (value & COUNT_OUTMASK) != that;
    }

    /// @notice Return the total number of votes recorded for the variant
    function getCount(uint256 value) internal pure returns (uint8) {
        return uint8(value);
    }
}

contract LidoOracle is ILidoOracle, Pausable {
    using ReportUtils for uint256;

    /// Maximum number of oracle committee members
    uint256 public constant MAX_MEMBERS = 255;
    // Missing member index
    uint256 internal constant MEMBER_NOT_FOUND = type(uint256).max;

    // Contract structured storage
    // Oracle members
    address[] private members;
    // Current era report  hashes
    uint256[] private currentReportVariants;
    // Current era reports
    StakeReport[]  private currentReportStake;
    // Then oracle member push report, its bit is set
    uint256   private currentReportBitmask;
    // Relaychain era timestamp
    RelaySpec private relaySpec;

    // todo pack it with eraId as uint8
    uint256  public quorum;
    uint64   public eraId;

    // Lido smart contract
    ILido    private lido;

    address  private member_manager;
    address  private quorum_manager;
    address  private spec_manager;

    // APY biases. low 16 bytes - slash (decrease) bias, high 16 bytes - reward (increase) bias
    uint256 private report_balance_bias;

    // todo remove
    constructor() public {
        initialize(address(0), msg.sender, msg.sender, msg.sender);
    }

    // todo remove.
    function _timestamp() external view returns (uint256){
        return block.timestamp;
    }

    // todo remove
    function _reportVariants() external view returns (uint256[] memory){
        return currentReportVariants;
    }

    // todo remove
    function _stakeReport(uint256 index) external view returns (StakeReport memory staking){
        return currentReportStake[index];
    }

    function initialize(
        address _lido,
        address _member_manager,
        address _quorum_manager,
        address _spec_manager
    ) internal {
        member_manager = _member_manager;
        quorum_manager = _quorum_manager;
        spec_manager = _spec_manager;

        lido = ILido(_lido);
        eraId = 0;

        _setRelaySpec(0, 0);
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


    /// convert a report into sha3 hash whose last byte is used to calc votes
    function getReportVariant(StakeReport calldata report) internal pure returns (uint256){
        bytes32 hash = keccak256(abi.encode(report));
        return uint256(hash) & ReportUtils.COUNT_OUTMASK;
    }

    /**
     * @notice advance era
     */
    function _clearReportingAndAdvanceTo(uint64 _eraId) internal {
        currentReportBitmask = 0;
        eraId = _eraId;

        delete currentReportVariants;
        delete currentReportStake;
        emit ExpectedEraIdUpdated(_eraId);
    }

    modifier auth(address manager) {
        require(msg.sender == manager, "FORBIDDEN");
        _;
    }

    function setLido(ILido _lido) external auth(spec_manager){
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
        // todo remove only non-voted member doesn't require flush report
        currentReportBitmask = 0;
        delete currentReportVariants;
        delete currentReportStake;
    }

    function _setRelaySpec(
        uint64 _genesisTimestamp,
        uint64 _secondsPerEra
    ) private {
        RelaySpec memory _relaySpec;
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
    function setQuorum(uint256 _quorum) external auth(quorum_manager) {
        require(0 != _quorum, "QUORUM_WONT_BE_MADE");
        uint256 oldQuorum = quorum;
        quorum = _quorum;
        emit QuorumChanged(_quorum);

        // If the quorum value lowered, check existing reports whether it is time to push
        if (oldQuorum > _quorum) {
            (bool isQuorum, uint256 reportIndex) = _getQuorumReport(_quorum);
            if (isQuorum) {
                _push(
                    eraId,
                    currentReportStake[reportIndex],
                    relaySpec
                );
            }
        }
        // todo emit event?
    }

    /**
    * @notice Return whether the `_quorum` is reached and the final report
    */
    function _getQuorumReport(uint256 _quorum) internal view returns (bool isQuorum, uint256 reportIndex) {
        // check most frequent cases first: all reports are the same or no reports yet
        if (currentReportVariants.length == 1) {
            return (currentReportVariants[0].getCount() >= _quorum, 0);
        } else if (currentReportVariants.length == 0) {
            return (false, MEMBER_NOT_FOUND);
        }

        // if more than 2 kind of reports exist, choose the most frequent
        uint256 maxind = 0;
        uint256 repeat = 0;
        uint16 maxval = 0;
        uint16 cur = 0;
        for (uint256 i = 0; i < currentReportVariants.length; ++i) {
            cur = currentReportVariants[i].getCount();
            if (cur >= maxval) {
                if (cur == maxval) {
                    ++repeat;
                } else {
                    maxind = i;
                    maxval = cur;
                    repeat = 0;
                }
            }
        }
        return (maxval >= _quorum && repeat == 0, maxind);
    }

    function _push(uint64 _eraId, StakeReport memory report, RelaySpec memory /* _relaySpec */) private {
        emit Completed(_eraId);

        _clearReportingAndAdvanceTo(_eraId + 1);

        // uint256 prevTotalStake = lido.totalSupply();
        lido.reportRelay(_eraId, report);
        // uint256 postTotalStake = lido.totalSupply();

        // todo add sanity check. ensure |prevTotalStake -  postTotalStake| is in report_balance_bias boundaries
    }

    function _getCurrentEraId(RelaySpec memory /* _relaySpec */) internal view returns (uint64) {
        // todo. uncomment and fix the expression
        return 0;
        //return ( uint64(block.timestamp) - _relaySpec.genesisTimestamp )/ _relaySpec.secondsPerEra;
    }

    /**
     * @notice Accept oracle committee member reports from the relay side
     * @param _eraId Relaychain era
     * @param staking Relaychain report
     */
    function reportRelay(uint64 _eraId, StakeReport calldata staking) external override whenNotPaused {
        RelaySpec memory _relaySpec = relaySpec;
        require(_eraId >= eraId, "ERA_IS_TOO_OLD");

        if (_eraId > eraId) {
            require(_eraId >= _getCurrentEraId(_relaySpec), "UNEXPECTED_ERA");
            _clearReportingAndAdvanceTo(_eraId);
        }

        uint256 index = _getMemberId(msg.sender);
        require(index != MEMBER_NOT_FOUND, "MEMBER_NOT_FOUND");

        uint256 mask = 1 << index;
        uint256 reportBitmask = currentReportBitmask;
        require(reportBitmask & mask == 0, "ALREADY_SUBMITTED");
        currentReportBitmask = (reportBitmask | mask);

        uint256 variant = getReportVariant(staking);
        uint256 _quorum = quorum;
        uint256 i = 0;

        // iterate on all report variants we already have, limited by the oracle members maximum
        while (i < currentReportVariants.length && currentReportVariants[i].isDifferent(variant)) ++i;
        if (i < currentReportVariants.length) {
            if (currentReportVariants[i].getCount() + 1 >= _quorum) {
                _push(_eraId, staking, _relaySpec);
            } else {
                ++currentReportVariants[i];
                // increment variant counter, see ReportUtils for details
            }
        } else {
            if (_quorum == 1) {
                _push(_eraId, staking, _relaySpec);
            } else {
                currentReportVariants.push(variant + 1);
                currentReportStake.push(staking);
            }
        }
    }

    function getStakeAccounts() external override view returns(bytes32[] memory){
        return lido.getStakeAccounts(eraId);
    }
}
