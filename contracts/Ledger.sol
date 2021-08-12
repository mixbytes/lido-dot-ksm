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

library LedgerUtils {
    /// @notice Return unlocking and withdrawable balances
    function getTotalUnlocking(ILidoOracle.LedgerData memory report, uint64 _eraId) internal pure returns (uint128, uint128){
        uint128 _total = 0;
        uint128 _withdrawble = 0;
        for (uint i = 0; i < report.unlocking.length; i++) {
            _total += report.unlocking[i].balance;
            if (report.unlocking[i].era >= _eraId) {
                _withdrawble += report.unlocking[i].balance;
            }
        }
        return (_total, _withdrawble);
    }
    /// @notice Return stash balance that can be freely transfer or allocated for stake
    function getFreeBalance(ILidoOracle.LedgerData memory report) internal pure returns (uint128){
        return report.stashBalance - report.totalBalance;
    }

    /// @notice Return true if report is consistent
    function isConsistent(ILidoOracle.LedgerData memory report) internal pure returns (bool){
        (uint128 _total, uint128 _withdrawable) = getTotalUnlocking(report, 0);
        return report.unlocking.length < type(uint8).max && report.totalBalance == (report.activeBalance + _total);
    }
}

abstract contract Consensus {
    using ReportUtils for uint256;

    event ExpectedEraIdUpdated(uint256 epochId);
    event Completed(uint256);

    event UpwardTransfer(uint128);
    event DownwardTransfer(uint128);
    event Rewards(uint128);
    event BondExtra(uint128);
    event Unbond(uint128);
    event Rebond(uint128);
    event Withdraw(uint128);

    event DownwardComplete(uint128);
    event UpwardComplete(uint128);

    event Sentinel(uint256 index, uint256 amount);

    // Current era report  hashes
    uint256[] internal currentReportVariants;
    // Current era reports
    ILidoOracle.LedgerData[]  private currentReports;
    // Then oracle member push report, its bit is set
    uint256   internal currentReportBitmask;
    // Current era Id
    uint64  internal eraId;

    function getStakeReport(uint256 index) internal view returns (ILidoOracle.LedgerData storage staking){
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
    using LedgerUtils for ILidoOracle.LedgerData;
    uint8   internal constant MAX_UNLOCKING_CHUNKS = 32;

    ILido private lido;
    ILidoOracle.StakeStatus internal stakeStatus;
    // todo take it into account
    uint64  private counter;
    // The total number of unlocking chunks
    uint8   private unlockingChunk;

    bytes32 public stashAccount;
    bytes32 public controllerAccount;
    // Stash balance that includes locked (bounded in stake) and free to transfer balance
    uint128 internal totalStashBalance;
    // Locked, or bonded in stake module, balance
    uint128 internal lockedStashBalance;
    // It's part of the bounded balance that can be released as free. todo remove from the contract
    // uint128 internal withdrawableBalance;
    // Active part of the bonded balance. todo remove from the contract
    // uint128 internal activeBalance;

    // Cached stash balance. It's the same as totalStashBalance but it's updated
    // only when rewards are distributed
    uint128 internal cachedStashBalance;

    // Pending transfers
    uint128 internal transferUpwardBalance;
    uint128 internal transferDownwardBalance;

    // Assign next transfer, withdraw, bond_extra or unbond.
    // If nonzero, it's extra balance that can be sent to parachain and deposited into stake
    uint128 internal deferUpwardBalance;
    // if nonzero it's demand to take back from stake
    uint128 internal deferDownwardBalance;

    // vKSM precompile
    IvKSM internal constant vKSM = IvKSM(0x0000000000000000000000000000000000000801);
    // AUX call builder precompile
    IAUX internal constant AUX = IAUX(0x0000000000000000000000000000000000000801);
    // Virtual accounts precompile
    IvAccounts internal constant vAccounts = IvAccounts(0x0000000000000000000000000000000000000801);
    // Who pay off relay chain transaction fees
    bytes32 internal constant GARANTOR = 0x00;

    modifier onlyLido() {
        require(msg.sender == address(lido), 'NOT_LIDO');
        _;
    }

    function initialize(bytes32 _stashAccount, bytes32 _controllerAccount, uint64 _startEraId) external {
        // The owner of the funds
        stashAccount = _stashAccount;
        // The account which handles bounded part of stash funds (unbond, rebond, withdraw, nominate)
        controllerAccount = _controllerAccount;
        stakeStatus = ILidoOracle.StakeStatus.None;
        // skip one era before start
        eraId = _startEraId + 1;

        lido = ILido(msg.sender);
    }

    function getEraId() external view returns (uint64){
        return eraId;
    }

    function deferStake(uint128 _upwardAmount, uint128 _downwardAmount) external onlyLido {
        require(_upwardAmount == 0 || _downwardAmount == 0);
        deferUpwardBalance = _upwardAmount;
        deferDownwardBalance = _downwardAmount;
    }

    function increaseDefer(uint128 _amount) external onlyLido {
        _increaseDefer(_amount);
    }

    function _increaseDefer(uint128 _amount) internal {
        if (deferDownwardBalance >= _amount) {
            deferDownwardBalance -= _amount;
        } else {
            deferUpwardBalance += (_amount - deferDownwardBalance);
            deferDownwardBalance = 0;
        }
    }

    function decreaseDefer(uint128 _amount) external onlyLido {
        _decreaseDefer(_amount);
    }

    function _decreaseDefer(uint128 _amount) internal {
        if (deferUpwardBalance >= _amount) {
            deferUpwardBalance -= _amount;
        } else {
            deferDownwardBalance += (_amount - deferUpwardBalance);
            deferUpwardBalance = 0;
        }
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

    function getPendingTransfer() external view returns (uint128, uint128){
        return (transferUpwardBalance, transferDownwardBalance);
    }

    function getDeferBalance() external view returns (uint128, uint128){
        return (deferUpwardBalance, deferDownwardBalance);
    }

    function clearReporting() external onlyLido {
        _clearReportingAndAdvanceTo(eraId);
    }

    function _push(uint64 _eraId, ILidoOracle.LedgerData memory report) internal override {
        require(stashAccount == report.stashAccount, 'STASH_ACCOUNT_MISMATCH');

        _clearReportingAndAdvanceTo(_eraId + 1);
        uint128 reportFreeBalance = report.getFreeBalance();
        //require(address(lido) != address(0),'NOT_A_LIDO');

        // wait for the downward transfer to complete
        if (transferDownwardBalance > 0) {
            uint128 _totalDownwardTransferred = uint128(vKSM.balanceOf(address(this)));

            // todo remove uint128 ledgerFreeBalance = (totalStashBalance - lockedStashBalance);
            // ensure that stash total balance has gone down.
            // note: external inflows into stash balance can break that condition and block subsequent operations
            if (_totalDownwardTransferred >= transferDownwardBalance ) {
                // take transferred funds into buffered balance
                vKSM.transfer(address(lido), transferDownwardBalance);
                //lido.increaseBufferedBalance(transferDownwardBalance, report.stashAccount);

                // exclude transferred amount from slashes
                // note!: transferDownwardBalance can be greater than cachedStashBalance
                cachedStashBalance -= transferDownwardBalance;

                emit DownwardComplete(transferDownwardBalance);
                // Clear transfer flag
                transferDownwardBalance = 0;
            }
        }

        // Wait for the upward transfer to complete
        if (transferUpwardBalance > 0) {
            uint128 ledgerFreeBalance = (totalStashBalance - lockedStashBalance);

            if (reportFreeBalance > ledgerFreeBalance) {
                // get transfer revenue
                reportFreeBalance -= ledgerFreeBalance;

                uint128 _amount = (transferUpwardBalance <= reportFreeBalance) ?
                transferUpwardBalance : reportFreeBalance;
                // Clear the transfer flag or decrease expected transfer value.
                // Note: Partial transfer cannot take place, but the stash can get funds from other accounts.
                transferUpwardBalance -= _amount;
                // Exclude transferred amount from rewards increasing cached value.
                cachedStashBalance += _amount;

                emit UpwardComplete(_amount);
            }
        }

        (uint128 _unlockingBalance, uint128 _withdrawableBalance) = report.getTotalUnlocking(_eraId);

        if (transferDownwardBalance == 0 && transferUpwardBalance == 0) {
            // Now all pending transfers have completed and a difference between stash balances
            // gives us accrued rewards (or looses ).
            if (report.stashBalance > cachedStashBalance) {
                lido.distributeRewards(report.stashBalance - cachedStashBalance, report.stashAccount);
                emit Rewards(report.stashBalance - cachedStashBalance);
                // sync cached balance with reported one
                cachedStashBalance = report.stashBalance;
            } else {
                // todo add losses handling. Now just delay the report
            }
            // todo add sanity check. Ensure |report.stashBalance - cachedStashBalance| is in report_balance_bias boundaries
            counter = 0;

            if (deferDownwardBalance > 0) {// rightside balance
                // to downward transfer
                uint128 _defer = (deferDownwardBalance <= reportFreeBalance) ? deferDownwardBalance : reportFreeBalance;
                emit Sentinel(0, _defer);
                bytes[] memory _calls = new bytes[](1);
                // withdraw_unbonded action and transfers are mutually exclusive,
                // so choose withdraw_unbonded if the stash has available.
                if (_withdrawableBalance > 0) {
                    // todo thin out withdraw request queue using odd-even or any other strategy
                    // todo add Rebond when free balance is enough to pay off redeem orders.
                    _calls[0] = AUX.buildWithdraw();
                    vAccounts.relayTransactCall(report.controllerAccount, GARANTOR, 0, _calls);
                    // todo Chill if active balance less then getMinStashBalance
                    emit Withdraw(_withdrawableBalance);
                } else if (_defer > 0) {
                    // todo! relayTransferFrom increase ledger not lido balance!
                    // todo! handle the case when _defer > cachedStashBalance
                    vAccounts.relayTransferFrom(report.stashAccount, _defer);
                    transferDownwardBalance += _defer;

                    _increaseDefer(_defer);

                    emit DownwardTransfer(_defer);
                }

                // to unlock
                _defer = deferDownwardBalance - _defer;
                // to unbond
                _defer -= (_defer <= _unlockingBalance) ? _defer : _unlockingBalance;
                // unbond extra
                if (_defer > 0 && _defer <= report.activeBalance && report.unlocking.length < MAX_UNLOCKING_CHUNKS) {
                    _calls[0] = AUX.buildUnBond(
                        ((report.activeBalance - _defer) < lido.getMinStashBalance()) ? report.activeBalance : _defer
                    );
                    vAccounts.relayTransactCall(report.controllerAccount, GARANTOR, 0, _calls);
                    emit Unbond(_defer);
                } else {
                    // todo if unlocking chunk's length exceeds MAX_UNLOCKING_CHUNKS, rebond last chunk and unbond again
                    // todo bond_extra, if transferDownwardBalance eq zero and the stash has some free balance
                }

            } else if (deferUpwardBalance >= 0) {// leftside balance
                // It should not have happened. Ignore this case.
                if (stakeStatus == ILidoOracle.StakeStatus.Blocked) {
                    return;
                }

                uint128 _defer = deferUpwardBalance;
                bytes[] memory _calls = new bytes[](1);
                // bond_extra and transfer are mutually exclusive, so if
                if (_defer > 0 && (_defer > reportFreeBalance || report.stakeStatus == ILidoOracle.StakeStatus.None)) {
                    // prefer transfer over stake

                    vKSM.transferFrom(address(lido), address(this), _defer);
                    vKSM.relayTransferTo(report.stashAccount, _defer);
                    transferUpwardBalance += _defer;

                    _decreaseDefer(_defer);

                    emit UpwardTransfer(_defer);
                    _defer = 0;

                } else {
                    // prefer stake over transfer

                    if (report.stakeStatus == ILidoOracle.StakeStatus.Nominator && reportFreeBalance > 0) {
                        // todo. Handle Idle,Blocked, Nominator and Validator statuses separately
                        // because it makes no sense to bond for Validator,
                        // and bonding extra funds for Idle doesn't give us a profit.
                        // Blocked status used to withdraw funds as a rule.
                        // Idle and None are for accumulation.
                        // We could bond funds for None status, but we leave this for {nominator} method.
                        _calls[0] = AUX.buildBondExtra(reportFreeBalance);
                        vAccounts.relayTransactCall(report.stashAccount, GARANTOR, 0, _calls);

                        emit BondExtra(reportFreeBalance);
                    }
                }

                if (_unlockingBalance > 0) {
                    // Always rebond unlocking tokens, if any.
                    // Thus, we flush a quite limited unbonding queue and increase active balance.
                    _calls[0] = AUX.buildReBond(_unlockingBalance);
                    vAccounts.relayTransactCall(report.controllerAccount, GARANTOR, 0, _calls);

                    emit Rebond(_unlockingBalance);
                }
            }
        } else {
            // increase error counter. todo stop ledger if counter exceeds the limit
            counter += 1;
        }

        if (transferDownwardBalance == 0) {
            // update ledger data from oracle report
            totalStashBalance = report.stashBalance;
            lockedStashBalance = report.totalBalance;
        }
        {
            // update withdrawableBalance  adding up all unlocked chunks whose era's greater than current
            // withdrawableBalance = _withdrawableBalance;
            unlockingChunk = uint8(report.unlocking.length);

            // skip blocked status as it serves as a marker of an unused ledger
            if (stakeStatus != ILidoOracle.StakeStatus.Blocked) {
                stakeStatus = report.stakeStatus;
            }
        }
        emit Completed(_eraId);
    }

    function reportRelay(uint256 index, uint256 quorum, uint64 _eraId, ILidoOracle.LedgerData calldata staking) external {
        if (_eraId > eraId) {
            _clearReportingAndAdvanceTo(_eraId);
        }
        require(stashAccount == staking.stashAccount, 'STASH_ACCOUNT_MISMATCH');

        require(lido.getOracle() == msg.sender, 'RESTRICTED_TO_ORACLE');
        _reportRelay(index, quorum, staking);
    }

    function softenQuorum(uint8 _quorum) external onlyLido {
        (bool isQuorum, uint256 reportIndex) = _getQuorumReport(_quorum);
        if (isQuorum) {
            ILidoOracle.LedgerData memory report = getStakeReport(reportIndex);
            _push(
                eraId, report
            );
        }
    }
}
