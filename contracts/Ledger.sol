// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";

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
    using SafeCast for uint256;

    event DownwardComplete(uint128 amount);
    event UpwardComplete(uint128 amount);
    event Rewards(uint128 amount);
    event Slash(uint128 amount);

    // ledger stash account
    bytes32 public stashAccount;

    // ledger controller account
    bytes32 public controllerAccount;

    // Stash balance that includes locked (bounded in stake) and free to transfer balance
    uint128 public totalBalance;

    // Locked, or bonded in stake module, balance
    uint128 public lockedBalance;

    // last reported active ledger balance
    uint128 public activeBalance;

    // last reported ledger status
    Types.LedgerStatus public status;

    // Cached stash balance. Need to calculate rewards between successfull up/down transfers
    uint128 public cachedTotalBalance;

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
        require(msg.sender == address(LIDO), "LEDGED: NOT_LIDO");
        _;
    }

    modifier onlyOracle() {
        address oracle = IOracleMaster(ILido(LIDO).ORACLE_MASTER()).getOracle(address(this));
        require(msg.sender == oracle, "LEDGED: NOT_ORACLE");
        _;
    }

    /**
    * @notice Initialize ledger contract.
    * @param _stashAccount - stash account id
    * @param _controllerAccount - controller account id
    * @param _vKSM - vKSM contract address
    * @param _AUX - AUX(relaychain calls builder) contract address
    * @param _vAccounts - vAccounts(relaychain calls relayer) contract address
    * @param _minNominatorBalance - minimal allowed nominator balance
    */
    function initialize(
        bytes32 _stashAccount,
        bytes32 _controllerAccount,
        address _vKSM,
        address _AUX,
        address _vAccounts,
        uint128 _minNominatorBalance
    ) external {
        require(address(vKSM) == address(0), "LEDGED: ALREADY_INITALIZED");

        // The owner of the funds
        stashAccount = _stashAccount;
        // The account which handles bounded part of stash funds (unbond, rebond, withdraw, nominate)
        controllerAccount = _controllerAccount;

        status = Types.LedgerStatus.None;

        LIDO = ILido(msg.sender);

        vKSM = IvKSM(_vKSM);
        AUX = IAUX(_AUX);
        vAccounts = IvAccounts(_vAccounts);

        MIN_NOMINATOR_BALANCE = _minNominatorBalance;
    }

    /**
    * @notice Set new minimal allowed nominator balance, allowed to call only by lido contract
    * @dev That method designed to be called by lido contract when relay spec is changed
    * @param _minNominatorBalance - minimal allowed nominator balance
    */
    function setMinNominatorBalance(uint128 _minNominatorBalance) external onlyLido {
        MIN_NOMINATOR_BALANCE = _minNominatorBalance;
    }

    /**
    * @notice Return target stake amount for this ledger
    * @return target stake amount
    */
    function targetStake() view public returns (uint256) {
        return LIDO.targetStake(address(this));
    }

    /**
    * @notice Nominate on behalf of this ledger, allowed to call only by lido contract
    * @dev Method spawns xcm call to relaychain.
    * @param _validators - array of choosen validator to be nominated
    */
    function nominate(bytes32[] calldata _validators) external onlyLido {
        require(activeBalance >= MIN_NOMINATOR_BALANCE, "LEDGED: NOT_ENOUGH_STAKE");
        bytes[] memory calls = new bytes[](1);
        calls[0] = AUX.buildNominate(_validators);
        vAccounts.relayTransactCallAll(controllerAccount, GARANTOR, 0, calls);
    }

    /**
    * @notice Provide portion of relaychain data about current ledger, allowed to call only by oracle contract
    * @dev Basically, ledger can obtain data from any source, but for now it allowed to recieve only from oracle.
           Method perform calculation of current state based on report data and saved state and expose
           required instructions(relaychain pallet calls) via xcm to adjust bonded amount to required target stake.
    * @param _eraId - reporting era id
    * @param _report - data that represent state of ledger on relaychain for `_eraId`
    */
    function pushData(uint64 _eraId, Types.OracleData memory _report) external onlyOracle {
        require(stashAccount == _report.stashAccount, "LEDGED: STASH_ACCOUNT_MISMATCH");

        status = _report.stakeStatus;
        activeBalance = _report.activeBalance;

        (uint128 unlockingBalance, uint128 withdrawableBalance) = _report.getTotalUnlocking(_eraId);
        uint128 nonWithdrawableBalance = unlockingBalance - withdrawableBalance;

        if (!_processRelayTransfers(_report)) {
            return;
        }

        if (cachedTotalBalance < _report.stashBalance) { // if cached balance > real => we have reward
            uint128 reward = _report.stashBalance - cachedTotalBalance;
            LIDO.distributeRewards(reward);

            emit Rewards(reward);
        }
        else if (cachedTotalBalance > _report.stashBalance) {
            //TODO handle losses
            uint128 slash = cachedTotalBalance - _report.stashBalance;
            emit Slash(slash);
        }

        bytes[] memory calls = new bytes[](5);
        uint16 calls_counter = 0;

        uint128 _targetStake = targetStake().toUint128();

        // relay deficit or bonding
        if (_report.stashBalance <= _targetStake) {
            //    Staking strategy:
            //     - upward transfer deficit tokens
            //     - rebond all unlocking tokens
            //     - bond_extra all free balance

            uint128 deficit = _targetStake - _report.stashBalance;

            // just upward transfer if we have deficit
            if (deficit > 0) {
                uint128 lidoBalance = uint128(vKSM.balanceOf(address(LIDO)));
                uint128 forTransfer = lidoBalance > deficit ? deficit : lidoBalance;

                vKSM.transferFrom(address(LIDO), address(this), forTransfer);
                vKSM.relayTransferTo(_report.stashAccount, forTransfer);
                transferUpwardBalance += forTransfer;
                deficit -= forTransfer;
            }

            // rebond all always
            if (unlockingBalance > 0) {
                calls[calls_counter++] = AUX.buildReBond(unlockingBalance);
            }

            uint128 relayFreeBalance = _report.getFreeBalance();

            if (relayFreeBalance > 0 &&
                (_report.stakeStatus == Types.LedgerStatus.Nominator || _report.stakeStatus == Types.LedgerStatus.Idle)) {
                calls[calls_counter++] = AUX.buildBondExtra(relayFreeBalance);
            } else if (_report.stakeStatus == Types.LedgerStatus.None && relayFreeBalance >= MIN_NOMINATOR_BALANCE) {
                calls[calls_counter++] = AUX.buildBond(controllerAccount, relayFreeBalance);
            }

        }
        else if (_report.stashBalance > _targetStake) { // parachain deficit
            //    Unstaking strategy:
            //     - try to downward transfer already free balance
            //     - if we still have deficit try to withdraw already unlocked tokens
            //     - if we still have deficit initiate unbond for remain deficit

            // if ledger is in the deadpool we need to put it to chill
            if (_targetStake < MIN_NOMINATOR_BALANCE && status != Types.LedgerStatus.Idle) {
                calls[calls_counter++] = AUX.buildChill();
            }

            uint128 deficit = _report.stashBalance - _targetStake;
            uint128 relayFreeBalance = _report.getFreeBalance();

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
                // todo drain stake if remaining balance is less than MIN_NOMINATOR_BALANCE
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
            vAccounts.relayTransactCallAll(_report.controllerAccount, GARANTOR, 0, calls_trimmed);
        }

        cachedTotalBalance = _report.stashBalance;
    }

    function _processRelayTransfers(Types.OracleData memory _report) internal returns(bool) {
        // wait for the downward transfer to complete
        if (transferDownwardBalance > 0) {
            uint128 totalDownwardTransferred = uint128(vKSM.balanceOf(address(this)));

            if (totalDownwardTransferred >= transferDownwardBalance ) {
                // take transferred funds into buffered balance
                vKSM.transfer(address(LIDO), transferDownwardBalance);

                // Clear transfer flag
                cachedTotalBalance -= transferDownwardBalance;
                transferDownwardBalance = 0;

                emit DownwardComplete(transferDownwardBalance);
            }
        }

        // wait for the upward transfer to complete
        if (transferUpwardBalance > 0) {
            uint128 ledgerFreeBalance = (totalBalance - lockedBalance);
            uint128 freeBalanceIncrement = _report.getFreeBalance() - ledgerFreeBalance;

            if (freeBalanceIncrement >= transferUpwardBalance) {
                cachedTotalBalance += transferUpwardBalance;

                emit UpwardComplete(transferUpwardBalance);
                transferUpwardBalance = 0;
            }
        }

        if (transferDownwardBalance == 0 && transferUpwardBalance == 0) {
            // update ledger data from oracle report
            totalBalance = _report.stashBalance;
            lockedBalance = _report.totalBalance;
            return true;
        }

        return false;
    }
}
