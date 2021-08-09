// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "../interfaces/ILidoOracle.sol";
import "../interfaces/ILido.sol";
import "../interfaces/IAUX.sol";
import "../interfaces/IvKSM.sol";
import "../interfaces/IvAccounts.sol";

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

abstract contract Consensus {
    using ReportUtils for uint256;

    event ExpectedEraIdUpdated(uint256 epochId);
    event Completed(uint256);

    // Current era report  hashes
    uint256[] internal currentReportVariants;
    // Current era reports
    ILidoOracle.LedgerData[]  private currentReports;
    // Then oracle member push report, its bit is set
    uint256   internal currentReportBitmask;
    // Current era Id
    uint64  internal eraId;

    function getStakeReport(uint256 index) internal view returns (ILidoOracle.LedgerData memory staking){
        assert(index < currentReports.length);
        return currentReports[index];
    }

    /**
    * @notice advance era
    */
    function _clearReportingAndAdvanceTo(uint64 _eraId) internal {
        currentReportBitmask = 0;
        eraId = _eraId;

        delete currentReportVariants;
        delete currentReports;
        emit ExpectedEraIdUpdated(_eraId);
    }

    function _push(uint64 _eraId, ILidoOracle.LedgerData memory report) virtual internal;

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

    //    function getWithdrawableBalance(ILidoOracle.LedgerData memory ledger, uint64 _eraId) internal pure returns (uint128){
    //        uint256 _balance = 0;
    //        for (uint i = 0; i < ledger.unlocking.length; i++) {
    //            if (ledger.unlocking[i].era >= _eraId) {
    //                _balance = _balance.add(ledger.unlocking[i].balance);
    //            }
    //        }
    //        return uint128(_balance);
    //    }

    /**
     * @notice Accept oracle report data
     * @param index oracle member index
     * @param quorum the minimum number of voted oracle members to accept a variant
     */
    function _reportRelay(uint256 index, uint256 quorum, ILidoOracle.LedgerData calldata staking) internal {
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
}

contract Ledger is Consensus {
    ILido private lido;
    ILidoOracle.StakeStatus internal stakeStatus;
    uint64  private counter;
    uint8   private unlockingChunk;

    //uint64  public startEra;
    bytes32 public stashAccount;
    bytes32 public controllerAccount;
    // stash balance that includes locked (bounded in stake) and free to transfer balance
    uint128 internal totalStashBalance;
    // locked, or bonded in stake module, balance
    uint128 internal lockedStashBalance;
    // part of the bounded balance that can be released as free
    uint128 internal withdrawableBalace;
    // active part of the bonded balance
    uint128 internal activeBalance;

    // cached stash balance. It's the same as totalStashBalance but it's updated
    // only when rewards are distributed
    uint128 internal cachedStashBalance;

    // pending transfers
    uint128 internal transferUpwardBalance;
    uint128 internal transferDownwardBalance;

    // AUX call builder precompile
    IAUX internal constant AUX = IAUX(0x0000000000000000000000000000000000000801);
    // Virtual accounts precompile
    IvAccounts internal constant vAccounts = IvAccounts(0x0000000000000000000000000000000000000801);

    modifier onlyLido() {
        require(msg.sender == address(lido), 'PRIVILEGED_LIDO');
        _;
    }

    function initialize(bytes32 _stashAccount, bytes32 _controllerAccount, uint64 _startEraId) external {
        // the owner of the funds
        stashAccount = _stashAccount;
        // the account which handle bounded part of stash funds
        controllerAccount = _controllerAccount;
        stakeStatus = ILidoOracle.StakeStatus.None;
        // skip one era before start
        eraId = _startEraId + 1;

        lido = ILido(msg.sender);
    }

    function getEraId() external view returns (uint64){
        return eraId;
    }

    function setStatus(ILidoOracle.StakeStatus _status) external onlyLido {
        stakeStatus = _status;
    }

    function getStatus() external view returns (ILidoOracle.StakeStatus){
        return stakeStatus;
    }

    function getTotalBalance() external view returns (uint128){
        return totalStashBalance;
    }

    function getFreeStashBalance() external view returns (uint128){
        return totalStashBalance - lockedStashBalance;
    }

    function getLockedStashBalance() external view returns (uint128){
        return lockedStashBalance;
    }

    function clearReporting() external onlyLido {
        _clearReportingAndAdvanceTo(eraId);
    }

    function _push(uint64 _eraId, ILidoOracle.LedgerData memory report) internal override {
        emit Completed(_eraId);

        _clearReportingAndAdvanceTo(_eraId + 1);
        // wait for downward transfer to complete
        if (transferDownwardBalance > 0) {
            uint128 _totalDownwardTransferred = lido.transferredBalance();

            uint128 reportFreeBalance = (report.stashBalance - report.totalBalance);
            uint128 ledgerFreeBalance = (totalStashBalance - lockedStashBalance);
            // ensure that stash total balance has gone down.
            // note: external inflows into stash balance can break that condition and block subsequent operations
            if (_totalDownwardTransferred >= transferDownwardBalance && ledgerFreeBalance > reportFreeBalance) {
                // take transferred funds into buffered balance
                lido.increaseBufferedBalance(transferDownwardBalance, report.stashAccount);

                // exclude transferred amount from slashes
                cachedStashBalance -= transferDownwardBalance;

                // clear transfer flag
                transferDownwardBalance = 0;
            }
        }

        // wait for upward transfer to complete
        if (transferUpwardBalance > 0) {
            uint128 reportFreeBalance = (report.stashBalance - report.totalBalance);
            uint128 ledgerFreeBalance = (totalStashBalance - lockedStashBalance);

            if (reportFreeBalance > ledgerFreeBalance) {

                reportFreeBalance -= ledgerFreeBalance;
                // clear or decrease transfer flag
                uint128 _amount = (transferUpwardBalance <= reportFreeBalance) ?
                    transferUpwardBalance : reportFreeBalance;

                transferUpwardBalance -= _amount;
                // exclude transferred amount from rewards
                cachedStashBalance+= _amount;
            }
        }

        if (transferDownwardBalance == 0 && transferUpwardBalance == 0 && report.stashBalance > cachedStashBalance) {
            lido.distributeRewards(report.stashBalance - cachedStashBalance, report.stashAccount);
            // sync cached balance
            cachedStashBalance = report.stashBalance;
            counter = 0;
            // todo start transfer and other action
        } else {
            counter += 1;
        }

        if (transferDownwardBalance == 0) {
            // update ledger data from oracle report
            totalStashBalance = report.stashBalance;
            lockedStashBalance = report.totalBalance;
            activeBalance = report.activeBalance;
        }
        {
            // update withdrawable part of the unbonding chunks
            uint128 _withdrawableBalance = 0;
            for (uint i = 0; i < report.unlocking.length; i++) {
                if (report.unlocking[i].era >= _eraId) {
                    _withdrawableBalance += report.unlocking[i].balance;
                }
            }
            withdrawableBalace = _withdrawableBalance;
            unlockingChunk = uint8(report.unlocking.length);

            // todo None and Blocked status handle
            stakeStatus = report.stakeStatus;
        }

        // todo add sanity check. ensure |prevTotalStake -  postTotalStake| is in report_balance_bias boundaries
    }

    function reportRelay(uint256 index, uint256 quorum, uint64 _eraId, ILidoOracle.LedgerData calldata staking) external {
        if (_eraId > eraId) {
            _clearReportingAndAdvanceTo(_eraId);
        }

        require(lido.getOracle() == msg.sender, 'RESTRICTED_TO_ORACLE');
        _reportRelay(index, quorum, staking);
    }

    function softenQuorum(uint8 _quorum) external onlyLido {
        (bool isQuorum, uint256 reportIndex) = _getQuorumReport(_quorum);
        if (isQuorum) {
            _push(
                eraId, getStakeReport(reportIndex)
            );
        }
    }
}
