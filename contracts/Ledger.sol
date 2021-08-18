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
            if (report.unlocking[i].era <= _eraId) {
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
    event Slash(uint128);
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

    ILido private lido;
    ILidoOracle.StakeStatus internal stakeStatus;

    bytes32 public stashAccount;
    bytes32 public controllerAccount;
    // Stash balance that includes locked (bounded in stake) and free to transfer balance
    uint128 public totalStashBalance;
    // Locked, or bonded in stake module, balance
    uint128 public lockedStashBalance;

    // Cached stash balance. Need to calculate rewards between successfull up/down transfers
    uint128 public cachedStashBalance;

    // Pending transfers
    uint128 internal transferUpwardBalance;
    uint128 internal transferDownwardBalance;

    // total users deposits + rewards - slashes (so just actual target stake amount)
    uint128 public targetStashStake;

    // vKSM precompile
    IvKSM internal vKSM;
    // AUX call builder precompile
    IAUX internal AUX;
    // Virtual accounts precompile
    IvAccounts internal vAccounts;
    // Who pay off relay chain transaction fees
    bytes32 internal constant GARANTOR = 0x00;

    modifier onlyLido() {
        require(msg.sender == address(lido), 'NOT_LIDO');
        _;
    }

    function initialize(
        bytes32 _stashAccount,
        bytes32 _controllerAccount,
        uint64 _startEraId,
        address _vKSM,
        address _AUX,
        address _vAccounts
    ) external {
        // The owner of the funds
        stashAccount = _stashAccount;
        // The account which handles bounded part of stash funds (unbond, rebond, withdraw, nominate)
        controllerAccount = _controllerAccount;
        stakeStatus = ILidoOracle.StakeStatus.None;
        // skip one era before start
        eraId = _startEraId + 1;

        lido = ILido(msg.sender);

        vKSM = IvKSM(_vKSM);
        AUX = IAUX(_AUX);
        vAccounts = IvAccounts(_vAccounts);
    }

    function getEraId() external view returns (uint64){
        return eraId;
    }

    function stake(uint128 _amount) external onlyLido {
        targetStashStake += _amount;
    }

    function unstake(uint128 _amount) external onlyLido {
        targetStashStake -= _amount;
    }

    function setStatus(ILidoOracle.StakeStatus _status) external onlyLido {
        stakeStatus = _status;
    }

    function getStatus() external view returns (ILidoOracle.StakeStatus){
        return stakeStatus;
    }

    function getFreeStashBalance() external view returns (uint128){
        return totalStashBalance - lockedStashBalance;
    }

    function clearReporting() external onlyLido {
        _clearReportingAndAdvanceTo(eraId);
    }

    function _processRelayTransfers(ILidoOracle.LedgerData memory report) internal returns(bool) {
        // wait for the downward transfer to complete
        if (transferDownwardBalance > 0) {
            uint128 totalDownwardTransferred = uint128(vKSM.balanceOf(address(this)));

            if (totalDownwardTransferred >= transferDownwardBalance ) {
                // take transferred funds into buffered balance
                vKSM.transfer(address(lido), transferDownwardBalance);

                // Clear transfer flag
                cachedStashBalance -= transferDownwardBalance;
                transferDownwardBalance = 0;

                emit DownwardComplete(transferDownwardBalance);
            }
        }

        // wait for the upward transfer to complete
        if (transferUpwardBalance > 0) {
            uint128 ledgerFreeBalance = (totalStashBalance - lockedStashBalance);
            uint128 freeBalanceIncrement = report.getFreeBalance() - ledgerFreeBalance;

            if (freeBalanceIncrement >= transferUpwardBalance) {
                cachedStashBalance += transferUpwardBalance;
                transferUpwardBalance = 0;

                emit UpwardComplete(transferUpwardBalance);
            }
        }

        if (transferDownwardBalance == 0 && transferUpwardBalance == 0) {
            // update ledger data from oracle report
            totalStashBalance = report.stashBalance;
            lockedStashBalance = report.totalBalance;
            return true;
        }

        return false;
    }

    function _push(uint64 _eraId, ILidoOracle.LedgerData memory report) internal override {
        require(stashAccount == report.stashAccount, 'STASH_ACCOUNT_MISMATCH');

        _clearReportingAndAdvanceTo(_eraId + 1);
        
        (uint128 unlockingBalance, uint128 withdrawableBalance) = report.getTotalUnlocking(_eraId);
        uint128 nonWithdrawableBalance = unlockingBalance - withdrawableBalance;

        if (!_processRelayTransfers(report)) {
            return;
        }

        if (cachedStashBalance < report.stashBalance) { // if cached balance > real => we have reward
            uint128 reward = report.stashBalance - cachedStashBalance;
            lido.distributeRewards(reward, report.stashAccount);
            targetStashStake += reward;
            emit Rewards(reward);
        }
        else if (cachedStashBalance > report.stashBalance) {
            //TODO handle losses
            uint128 slash = cachedStashBalance - report.stashBalance;
            emit Slash(slash);
            targetStashStake -= slash;
        }

        bytes[] memory calls = new bytes[](5);
        uint16 calls_counter = 0;
            
        // relay deficit or bonding
        if (report.stashBalance <= targetStashStake) {
            //    Staking strategy:
            //     - upward transfer deficit tokens
            //     - rebond all unlocking tokens
            //     - bond_extra all free balance

            uint128 deficit = targetStashStake - report.stashBalance;

            // just upward transfer if we have deficit
            if (deficit > 0) {
                vKSM.transferFrom(address(lido), address(this), deficit);
                vKSM.relayTransferTo(report.stashAccount, deficit);
                transferUpwardBalance += deficit;
            }

            // rebond all always
            if (unlockingBalance > 0) {
                calls[calls_counter++] = AUX.buildReBond(unlockingBalance);
            }

            // bond extra all free balance always
            if (report.getFreeBalance() > 0) {
                calls[calls_counter++] = AUX.buildBondExtra(report.getFreeBalance());
            }
        }
        else if (report.stashBalance > targetStashStake) { // parachain deficit
            //    Unstaking strategy:
            //     - try to downward transfer already free balance
            //     - if we still have deficit try to withdraw already unlocked tokens
            //     - if we still have deficit initiate unbond for remain deficit

            uint128 deficit = report.stashBalance - targetStashStake;
            uint128 relayFreeBalance = report.getFreeBalance();

            // need to downward transfer if we have some free
            if (relayFreeBalance > 0) {
                uint128 forTransfer = relayFreeBalance > deficit ? deficit : relayFreeBalance;
                vAccounts.relayTransferFrom(stashAccount, forTransfer);
                transferDownwardBalance += forTransfer;
                deficit -= forTransfer;
                relayFreeBalance -= forTransfer;
            }
            
            // withdraw if we have some unlocked
            if (deficit > 0 && withdrawableBalance > 0) { 
                calls[calls_counter++] = AUX.buildWithdraw();
                deficit -= withdrawableBalance > deficit ? deficit : withdrawableBalance;
            }

            // need to unbond if we still have deficit
            if (deficit > 0 && nonWithdrawableBalance < deficit) {
                uint128 forUnbond = deficit - nonWithdrawableBalance;
                calls[calls_counter++] = AUX.buildUnBond(deficit - nonWithdrawableBalance);
                deficit -= forUnbond;
            }

            // bond all remain free balance
            if (relayFreeBalance > 0) {
                calls[calls_counter++] = AUX.buildBondExtra(relayFreeBalance);
            }
        }

        if (calls_counter > 0) {
            bytes[] memory calls_trimmed = new bytes[](calls_counter);
            for (uint16 i = 0; i < calls_counter; ++i) {
                calls_trimmed[i] = calls[i];
            }
            vAccounts.relayTransactCallAll(report.controllerAccount, GARANTOR, 0, calls_trimmed);
        }

        cachedStashBalance = report.stashBalance;
        
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
