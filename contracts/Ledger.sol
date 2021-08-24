// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "../interfaces/IOracleMaster.sol";
import "../interfaces/ILido.sol";
import "../interfaces/IAUX.sol";
import "../interfaces/IvKSM.sol";
import "../interfaces/IvAccounts.sol";
import "../interfaces/Types.sol";

import "./utils/LedgerUtils.sol";
import "./utils/ReportUtils.sol";



contract Ledger {
    using LedgerUtils for Types.OracleData;

    event DownwardComplete(uint128);
    event UpwardComplete(uint128);
    event Rewards(uint128);
    event Slash(uint128);


    // ledger stash account
    bytes32 public stashAccount;

    // ledger controller account
    bytes32 public controllerAccount;

    // Stash balance that includes locked (bounded in stake) and free to transfer balance
    uint128 public totalStashBalance;

    // Locked, or bonded in stake module, balance
    uint128 public lockedStashBalance;

    // last reported active ledger balance
    uint128 public activeStashBalance;

    // last reported ledger status
    Types.LedgerStatus public stakeStatus;

    // Cached stash balance. Need to calculate rewards between successfull up/down transfers
    uint128 public cachedStashBalance;

    // total users deposits + rewards - slashes (so just actual target stake amount)
    uint128 public targetStashStake;

    // Pending transfers
    uint128 public transferUpwardBalance;
    uint128 public transferDownwardBalance;


    // vKSM precompile
    IvKSM internal vKSM;
    // AUX call builder precompile
    IAUX internal AUX;
    // Virtual accounts precompile
    IvAccounts internal vAccounts;


    // Lido main contract address
    ILido public LIDO;

    // Minimal allowed balance to being a nominator
    uint128 public MIN_NOMINATOR_BALANCE;


    // Who pay off relay chain transaction fees
    bytes32 internal constant GARANTOR = 0x00;



    modifier onlyLido() {
        require(msg.sender == address(LIDO), "NOT_LIDO");
        _;
    }

    modifier onlyOracle() {
        address oracle = IOracleMaster(ILido(LIDO).getOracleMaster()).getOracle(address(this));
        require(msg.sender == oracle, "NOT_ORACLE");
        _;
    }

    function initialize(
        bytes32 _stashAccount,
        bytes32 _controllerAccount,
        address _vKSM,
        address _AUX,
        address _vAccounts,
        uint128 _minNominatorBalance
    ) external {
        require(stashAccount == 0x0, "ALREADY_INITALIZED");

        // The owner of the funds
        stashAccount = _stashAccount;
        // The account which handles bounded part of stash funds (unbond, rebond, withdraw, nominate)
        controllerAccount = _controllerAccount;

        stakeStatus = Types.LedgerStatus.None;

        LIDO = ILido(msg.sender);

        vKSM = IvKSM(_vKSM);
        AUX = IAUX(_AUX);
        vAccounts = IvAccounts(_vAccounts);

        MIN_NOMINATOR_BALANCE = _minNominatorBalance;
    }

    function setMinNominatorBalance(uint128 _minNominatorBalance) external onlyLido {
        MIN_NOMINATOR_BALANCE = _minNominatorBalance;
    }

    function exactStake(uint128 _amount) external onlyLido {
        targetStashStake = _amount;
    }

    function stake(uint128 _amount) external onlyLido {
        targetStashStake += _amount;
    }

    function unstake(uint128 _amount) external onlyLido {
        targetStashStake -= _amount;
    }

    function nominate(bytes32[] calldata validators) external onlyLido {
        require(activeStashBalance >= LIDO.getMinStashBalance(), "NOT_ENOUGH_STAKE");
        bytes[] memory calls = new bytes[](1);
        calls[0] = AUX.buildNominate(validators);
        vAccounts.relayTransactCallAll(controllerAccount, GARANTOR, 0, calls);
    }

    function getStatus() external view returns (Types.LedgerStatus) {
        return stakeStatus;
    }

    function _processRelayTransfers(Types.OracleData memory report) internal returns(bool) {
        // wait for the downward transfer to complete
        if (transferDownwardBalance > 0) {
            uint128 totalDownwardTransferred = uint128(vKSM.balanceOf(address(this)));

            if (totalDownwardTransferred >= transferDownwardBalance ) {
                // take transferred funds into buffered balance
                vKSM.transfer(address(LIDO), transferDownwardBalance);

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

    function pushData(uint64 _eraId, Types.OracleData memory report) external onlyOracle {
        require(stashAccount == report.stashAccount, "STASH_ACCOUNT_MISMATCH");

        stakeStatus = report.stakeStatus;
        activeStashBalance = report.activeBalance;
        
        (uint128 unlockingBalance, uint128 withdrawableBalance) = report.getTotalUnlocking(_eraId);
        uint128 nonWithdrawableBalance = unlockingBalance - withdrawableBalance;

        if (!_processRelayTransfers(report)) {
            return;
        }

        if (cachedStashBalance < report.stashBalance) { // if cached balance > real => we have reward
            uint128 reward = report.stashBalance - cachedStashBalance;
            LIDO.distributeRewards(reward);

            // if targetStash is zero we need to keep it zero to drain all active balance
            if (targetStashStake != 0) {
                targetStashStake += reward;
            }
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
                uint128 lidoBalance = uint128(vKSM.balanceOf(address(LIDO)));
                uint128 forTransfer = lidoBalance > deficit ? deficit : lidoBalance;

                vKSM.transferFrom(address(LIDO), address(this), forTransfer);
                vKSM.relayTransferTo(report.stashAccount, forTransfer);
                transferUpwardBalance += forTransfer;
                deficit -= forTransfer;
            }

            // rebond all always
            if (unlockingBalance > 0) {
                calls[calls_counter++] = AUX.buildReBond(unlockingBalance);
            }

            //TODO if status is idle send bond first
            // bond extra all free balance always
            if (report.getFreeBalance() > 0) {
                if (activeStashBalance == 0) {
                    calls[calls_counter++] = AUX.buildBond(controllerAccount, report.getFreeBalance());
                }
                else {
                    calls[calls_counter++] = AUX.buildBondExtra(report.getFreeBalance());
                }
            }
        }
        else if (report.stashBalance > targetStashStake) { // parachain deficit
            //    Unstaking strategy:
            //     - try to downward transfer already free balance
            //     - if we still have deficit try to withdraw already unlocked tokens
            //     - if we still have deficit initiate unbond for remain deficit

            // if ledger is in the deadpool we need to put it to chill 
            if (targetStashStake < MIN_NOMINATOR_BALANCE && stakeStatus != Types.LedgerStatus.Idle) {
                calls[calls_counter++] = AUX.buildChill();
            }

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
    }
}
