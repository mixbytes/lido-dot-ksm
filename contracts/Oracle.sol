// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "../interfaces/Types.sol";
import "../interfaces/ILedger.sol";
import "../interfaces/IOracleMaster.sol";

import "./utils/ReportUtils.sol";


contract Oracle {
    using ReportUtils for uint256;

    event Completed(uint256);
    
    address public oracleMaster;
    address public ledger;
    address public oracleClone;

    // Current era report  hashes
    uint256[] internal currentReportVariants;
    // Current era reports
    Types.OracleData[]  private currentReports;
    // Then oracle member push report, its bit is set
    uint256   internal currentReportBitmask;
    
    modifier onlyOracleMaster() {
        require(msg.sender == oracleMaster);
        _;
    }

    function initialize(address _oracleMaster, address _ledger) external {
        require(oracleMaster == address(0), 'ALREADY_INITIALIZED');
        oracleMaster = _oracleMaster;
        ledger = _ledger;
    }

    function getStakeReport(uint256 index) internal view returns (Types.OracleData storage staking) {
        assert(index < currentReports.length);
        return currentReports[index];
    }

    /**
    * @notice advance era
    */
    function _cleanReporting() internal {
        currentReportBitmask = 0;

        delete currentReportVariants;
        delete currentReports;
    }

    function _push(uint64 _eraId, Types.OracleData memory report) internal {
        ILedger(ledger).pushData(_eraId, report);

        _cleanReporting();
    }

    /**
    * @notice Return whether the `_quorum` is reached and the final report can be pushed
    */
    function _getQuorumReport(uint256 _quorum) internal view returns (bool isQuorum, uint256 reportIndex) {
        // check most frequent cases first: all reports are the same or no reports yet
        if (currentReportVariants.length == 1) {
            return (currentReportVariants[0].getCount() >= _quorum, 0);
        } else if (currentReportVariants.length == 0) {
            return (false, type(uint256).max);
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

    /**
     * @notice Accept oracle report data
     * @param index oracle member index
     * @param quorum the minimum number of voted oracle members to accept a variant
     */
    function reportRelay(uint256 index, uint256 quorum, uint64 eraId, Types.OracleData calldata staking) external onlyOracleMaster {
        uint256 mask = 1 << index;
        uint256 reportBitmask = currentReportBitmask;
        require(reportBitmask & mask == 0, "ALREADY_SUBMITTED");
        currentReportBitmask = (reportBitmask | mask);

        // convert staking report into 31 byte hash. The last byte is used for vote counting
        uint256 variant = uint256(keccak256(abi.encode(staking))) & ReportUtils.COUNT_OUTMASK;

        uint256 i = 0;

        // iterate on all report variants we already have, limited by the oracle members maximum
        while (i < currentReportVariants.length && currentReportVariants[i].isDifferent(variant)) ++i;
        if (i < currentReportVariants.length) {
            if (currentReportVariants[i].getCount() + 1 >= quorum) {
                _push(eraId, staking);
                _cleanReporting();
            } else {
                ++currentReportVariants[i];
                // increment variant counter, see ReportUtils for details
            }
        } else {
            if (quorum == 1) {
                _push(eraId, staking);
            } else {
                currentReportVariants.push(variant + 1);
                currentReports.push(staking);
            }
        }
    }

    function softenQuorum(uint8 _quorum, uint64 _eraId) external onlyOracleMaster {
        (bool isQuorum, uint256 reportIndex) = _getQuorumReport(_quorum);
        if (isQuorum) {
            Types.OracleData memory report = getStakeReport(reportIndex);
            _push(
                _eraId, report
            );
            _cleanReporting();
        }
    }

    function cleanReporting() external onlyOracleMaster {
        _cleanReporting();
    }
}
