// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "../interfaces/IOracleMaster.sol";
import "../interfaces/ILido.sol";
import "../interfaces/IAuthManager.sol";
import "../interfaces/IRelayEncoder.sol";
import "../interfaces/IXcmTransactor.sol";
import "../interfaces/IController.sol";
import "../interfaces/Types.sol";

import "./utils/LedgerUtils.sol";
import "./utils/ReportUtils.sol";



contract Ledger {
    using LedgerUtils for Types.OracleData;
    using SafeCast for uint256;

    event DownwardComplete(uint128 amount);
    event UpwardComplete(uint128 amount);
    event Rewards(uint128 amount, uint128 balance);
    event Slash(uint128 amount, uint128 balance);

    // Lido main contract address
    ILido public LIDO;

    // vKSM precompile
    IERC20 internal VKSM;

    // controller for sending xcm messages to relay chain
    IController internal CONTROLLER;

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

    // Pending bonding
    uint128 public pendingBonds;

    // Minimal allowed balance to being a nominator
    uint128 public MIN_NOMINATOR_BALANCE;

    // Minimal allowable active balance
    uint128 public MINIMUM_BALANCE;

    // Ledger manager role
    bytes32 internal constant ROLE_LEDGER_MANAGER = keccak256("ROLE_LEDGER_MANAGER");

    // Maximum allowable unlocking chunks amount
    uint256 public MAX_UNLOCKING_CHUNKS;

    // Allows function calls only from LIDO
    modifier onlyLido() {
        require(msg.sender == address(LIDO), "LEDGER: NOT_LIDO");
        _;
    }

    // Allows function calls only from Oracle
    modifier onlyOracle() {
        address oracle = IOracleMaster(ILido(LIDO).ORACLE_MASTER()).getOracle(address(this));
        require(msg.sender == oracle, "LEDGER: NOT_ORACLE");
        _;
    }

    // Allows function calls only from member with specific role
    modifier auth(bytes32 role) {
        require(IAuthManager(ILido(LIDO).AUTH_MANAGER()).has(role, msg.sender), "LEDGER: UNAUTHOROZED");
        _;
    }

    /**
    * @notice Initialize ledger contract.
    * @param _stashAccount - stash account id
    * @param _controllerAccount - controller account id
    * @param _vKSM - vKSM contract address
    * @param _controller - xcmTransactor(relaychain calls relayer) contract address
    * @param _minNominatorBalance - minimal allowed nominator balance
    * @param _lido - LIDO address
    * @param _minimumBalance - minimal allowed active balance for ledger
    * @param _maxUnlockingChunks - maximum amount of unlocking chunks
    */
    function initialize(
        bytes32 _stashAccount,
        bytes32 _controllerAccount,
        address _vKSM,
        address _controller,
        uint128 _minNominatorBalance,
        address _lido,
        uint128 _minimumBalance,
        uint256 _maxUnlockingChunks
    ) external {
        require(_vKSM != address(0), "LEDGER: INCORRECT_VKSM");
        require(address(VKSM) == address(0), "LEDGER: ALREADY_INITIALIZED");

        // The owner of the funds
        stashAccount = _stashAccount;
        // The account which handles bounded part of stash funds (unbond, rebond, withdraw, nominate)
        controllerAccount = _controllerAccount;

        status = Types.LedgerStatus.None;

        LIDO = ILido(_lido);

        VKSM = IERC20(_vKSM);

        CONTROLLER = IController(_controller);

        MIN_NOMINATOR_BALANCE = _minNominatorBalance;

        MINIMUM_BALANCE = _minimumBalance;
        
        MAX_UNLOCKING_CHUNKS = _maxUnlockingChunks;

        _refreshAllowances();
    }

    /**
    * @notice Set new minimal allowed nominator balance and minimal active balance, allowed to call only by lido contract
    * @dev That method designed to be called by lido contract when relay spec is changed
    * @param _minNominatorBalance - minimal allowed nominator balance
    * @param _minimumBalance - minimal allowed ledger active balance
    * @param _maxUnlockingChunks - maximum amount of unlocking chunks
    */
    function setRelaySpecs(uint128 _minNominatorBalance, uint128 _minimumBalance, uint256 _maxUnlockingChunks) external onlyLido {
        MIN_NOMINATOR_BALANCE = _minNominatorBalance;
        MINIMUM_BALANCE = _minimumBalance;
        MAX_UNLOCKING_CHUNKS = _maxUnlockingChunks;
    }

    /**
    * @notice Refresh allowances for ledger
    */
    function refreshAllowances() external auth(ROLE_LEDGER_MANAGER) {
        _refreshAllowances();
    }

    /**
    * @notice Return target stake amount for this ledger
    * @return target stake amount
    */
    function ledgerStake() public view returns (uint256) {
        return LIDO.ledgerStake(address(this));
    }

    /**
    * @notice Return true if ledger doesn't have any funds
    */
    function isEmpty() external view returns (bool) {
        return totalBalance == 0 && transferUpwardBalance == 0 && transferDownwardBalance == 0;
    }

    /**
    * @notice Nominate on behalf of this ledger, allowed to call only by lido contract
    * @dev Method spawns xcm call to relaychain.
    * @param _validators - array of choosen validator to be nominated
    */
    function nominate(bytes32[] calldata _validators) external onlyLido {
        require(activeBalance >= MIN_NOMINATOR_BALANCE, "LEDGER: NOT_ENOUGH_STAKE");
        CONTROLLER.nominate(_validators);
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
        require(stashAccount == _report.stashAccount, "LEDGER: STASH_ACCOUNT_MISMATCH");

        status = _report.stakeStatus;
        activeBalance = _report.activeBalance;

        (uint128 unlockingBalance, uint128 withdrawableBalance) = _report.getTotalUnlocking(_eraId);

        if (!_processRelayTransfers(_report)) {
            return;
        }
        uint128 _cachedTotalBalance = cachedTotalBalance;
        
        if (cachedTotalBalance > 0) {
            uint128 relativeDifference = _report.stashBalance > cachedTotalBalance ? 
                _report.stashBalance - cachedTotalBalance :
                cachedTotalBalance - _report.stashBalance;
            // NOTE: 1 / 10000 - one base point
            relativeDifference = relativeDifference * 10000 / cachedTotalBalance;
            require(relativeDifference < LIDO.MAX_ALLOWABLE_DIFFERENCE(), "LEDGER: DIFFERENCE_EXCEEDS_BALANCE");
        }

        if (_cachedTotalBalance < _report.stashBalance) { // if cached balance > real => we have reward
            uint128 reward = _report.stashBalance - _cachedTotalBalance;
            LIDO.distributeRewards(reward, _report.stashBalance);

            emit Rewards(reward, _report.stashBalance);
        }
        else if (_cachedTotalBalance > _report.stashBalance) {
            uint128 slash = _cachedTotalBalance - _report.stashBalance;
            LIDO.distributeLosses(slash, _report.stashBalance);

            emit Slash(slash, _report.stashBalance);
        }

        uint128 _ledgerStake = ledgerStake().toUint128();

        // Always transfer deficit to relay chain
        if (_report.stashBalance < _ledgerStake) {
            uint128 deficit = _ledgerStake - _report.stashBalance;
            LIDO.transferToLedger(deficit);
            CONTROLLER.transferToRelaychain(deficit);
            transferUpwardBalance += deficit;
        }

        uint128 relayFreeBalance = _report.getFreeBalance();
        pendingBonds = 0; // Always set bonds to zero (if we have old free balance then it will bond again)

        if (activeBalance < _ledgerStake) {
            // NOTE: if ledger stake > active balance we are trying to bond all funds
            uint128 diff = _ledgerStake - activeBalance;
            uint128 diffToRebond = diff > unlockingBalance ? unlockingBalance : diff;
            if (diffToRebond > 0) {
                CONTROLLER.rebond(diffToRebond, MAX_UNLOCKING_CHUNKS);
                diff -= diffToRebond;
            }

            if ((relayFreeBalance == transferUpwardBalance) && (transferUpwardBalance > 0)) {
                // In case if bond amount = transferUpwardBalance we can't distinguish 2 messages were success or 2 masseges were failed
                relayFreeBalance -= 1;
            }

            if ((diff > 0) && (relayFreeBalance > 0)) {    
                uint128 diffToBond = diff > relayFreeBalance ? relayFreeBalance : diff;
                if (_report.stakeStatus == Types.LedgerStatus.Nominator || _report.stakeStatus == Types.LedgerStatus.Idle) {
                    CONTROLLER.bondExtra(diffToBond);
                    pendingBonds = diffToBond;
                } else if (_report.stakeStatus == Types.LedgerStatus.None && relayFreeBalance >= MIN_NOMINATOR_BALANCE) {
                    CONTROLLER.bond(controllerAccount, diffToBond);
                    pendingBonds = diffToBond;
                }
                relayFreeBalance -= diffToBond;
            }
        }
        else {
            if (_ledgerStake < MIN_NOMINATOR_BALANCE && status != Types.LedgerStatus.Idle && activeBalance > 0) {
                CONTROLLER.chill();
            }

            // NOTE: if ledger stake < active balance we unbond
            uint128 diff = activeBalance - _ledgerStake;
            if (diff > 0) {
                CONTROLLER.unbond(diff);
            }

            // NOTE: if ledger stake == active balance we only withdraw unlocked balance
            if (withdrawableBalance > 0) {
                uint32 slashSpans = 0;
                if ((_report.unlocking.length == 0) && (_report.activeBalance <= MINIMUM_BALANCE)) {
                    slashSpans = _report.slashingSpans;
                }
                CONTROLLER.withdrawUnbonded(slashSpans);
            }
        }
        
        // NOTE: always transfer all free baalance to parachain
        if (relayFreeBalance > 0) {
            CONTROLLER.transferToParachain(relayFreeBalance);
            transferDownwardBalance += relayFreeBalance;
        }

        cachedTotalBalance = _report.stashBalance;
    }

    /**
    * @notice Await for all transfers from/to relay chain
    * @param _report - data that represent state of ledger on relaychain
    */
    function _processRelayTransfers(Types.OracleData memory _report) internal returns(bool) {
        // wait for the downward transfer to complete
        uint128 _transferDownwardBalance = transferDownwardBalance;
        if (_transferDownwardBalance > 0) {
            uint128 totalDownwardTransferred = uint128(VKSM.balanceOf(address(this)));

            if (totalDownwardTransferred >= _transferDownwardBalance ) {
                // NOTE: all excesses go to developers)
                if (totalDownwardTransferred > _transferDownwardBalance ) {
                    VKSM.transfer(LIDO.developers(), totalDownwardTransferred - _transferDownwardBalance);
                }

                // send all funds to lido
<<<<<<< HEAD
                LIDO.transferFromLedger(_transferDownwardBalance, totalDownwardTransferred - _transferDownwardBalance);
=======
                LIDO.transferFromLedger(_transferDownwardBalance);
>>>>>>> 2d3addb (Fix underflow when ledger borrow lost peg due to excesses)

                // Clear transfer flag
                cachedTotalBalance -= _transferDownwardBalance;
                transferDownwardBalance = 0;

                emit DownwardComplete(_transferDownwardBalance);
                _transferDownwardBalance = 0;
            }
        }

        // wait for the upward transfer to complete
        uint128 _transferUpwardBalance = transferUpwardBalance;
        if (_transferUpwardBalance > 0) {
            // NOTE: pending Bonds allows to control balance which was bonded in previous era, but not in lockedBalance yet
            // (see single_ledger_test:test_equal_deposit_bond)
            uint128 ledgerFreeBalance = (totalBalance - lockedBalance);
            int128 freeBalanceDiff = int128(_report.getFreeBalance()) - int128(ledgerFreeBalance);
            int128 expectedBalanceDiff = int128(transferUpwardBalance) - int128(pendingBonds);

            if (freeBalanceDiff >= expectedBalanceDiff) {
                cachedTotalBalance += _transferUpwardBalance;

                transferUpwardBalance = 0;
                // pendingBonds = 0;
                emit UpwardComplete(_transferUpwardBalance);
                _transferUpwardBalance = 0;
            }
        }

        if (_transferDownwardBalance == 0 && _transferUpwardBalance == 0) {
            // update ledger data from oracle report
            totalBalance = _report.stashBalance;
            lockedBalance = _report.totalBalance;
            return true;
        }

        return false;
    }

    /**
    * @notice Refresh allowances for ledger
    */
    function _refreshAllowances() internal {
        VKSM.approve(address(LIDO), type(uint256).max);
        VKSM.approve(address(CONTROLLER), type(uint256).max);
    }
}
