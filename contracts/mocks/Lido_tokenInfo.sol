// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../../interfaces/IOracleMaster.sol";
import "../../interfaces/ILedgerFactory.sol";
import "../../interfaces/ILedger.sol";
import "../../interfaces/IController.sol";
import "../../interfaces/IAuthManager.sol";
import "../../interfaces/IWithdrawal.sol";

import "../stKSM.sol";


contract LidoToken is stKSM, Initializable {
    using SafeCast for uint256;

    // Records a deposit made by a user
    event Deposited(address indexed sender, uint256 amount);

    // Created redeem order
    event Redeemed(address indexed receiver, uint256 amount);

    // Claimed vKSM tokens back
    event Claimed(address indexed receiver, uint256 amount);

    // Fee was updated
    event FeeSet(uint16 fee, uint16 feeOperatorsBP, uint16 feeTreasuryBP,  uint16 feeDevelopersBP);

    // Rewards distributed
    event Rewards(address ledger, uint256 rewards, uint256 balance);

    // Losses distributed
    event Losses(address ledger, uint256 losses, uint256 balance);

    // Added new ledger
    event LedgerAdd(
        address addr,
        bytes32 stashAccount,
        bytes32 controllerAccount
    );

    // Ledger removed
    event LedgerRemove(
        address addr
    );

    // Ledger disabled
    event LedgerDisable(
        address addr
    );

    // Ledger paused
    event LedgerPaused(
        address addr
    );

    // Ledger resumed
    event LedgerResumed(
        address addr
    );

    // Referral program
    event Referral(
        address userAddr,
        address referralAddr,
        uint256 amount,
        uint256 shares
    );

    // sum of all deposits and rewards
    uint256 public fundRaisedBalance;

    // haven't executed buffrered deposits:
    //
    // this is the amount of funds that must either sent to the ledgers
    // or rebalanced to buffered redeems
    uint256 public bufferedDeposits;

    // haven't executed buffrered redeems:
    // this is the amount of funds that should be sent to the WITHDRAWAL contract
    uint256 public bufferedRedeems;

    // this is the active stake on the ledger = [ledgerBorrow] - unbonded funds - free funds
    mapping(address => uint256) public ledgerStake;

    // this is the total amount of funds in the ledger = active stake + unbonded funds + free funds
    mapping(address => uint256) public ledgerBorrow;

    // Disabled ledgers
    address[] private disabledLedgers;

    // Enabled ledgers
    address[] private enabledLedgers;

    // Cap for deposits for v1
    uint256 public depositCap;

    // vKSM precompile
    IERC20 private VKSM;

    // controller
    address private CONTROLLER;

    // auth manager contract address
    address public AUTH_MANAGER;

    // Maximum number of ledgers
    uint256 private MAX_LEDGERS_AMOUNT;

    // oracle master contract
    address public ORACLE_MASTER;

    // relay spec
    Types.RelaySpec private RELAY_SPEC;

    // developers fund
    address private developers;

    // treasury fund
    address private treasury;

    // ledger beacon
    address public LEDGER_BEACON;

    // ledger factory
    address private LEDGER_FACTORY;

    // withdrawal contract
    address private WITHDRAWAL;

    // Max allowable difference for oracle reports
    uint128 public MAX_ALLOWABLE_DIFFERENCE;

    // Ledger address by stash account id
    mapping(bytes32 => address) private ledgerByStash;

    // Map to check ledger existence by address
    mapping(address => bool) private ledgerByAddress;

    // Map to check ledger paused to redeem state
    mapping(address => bool) private pausedledgers;

    /* fee interest in basis points.
    It's packed uint256 consist of three uint16 (total_fee, treasury_fee, developers_fee).
    where total_fee = treasury_fee + developers_fee + 3000 (3% operators fee)
    */
    Types.Fee private FEE;

    // default interest value in base points.
    uint16 internal constant DEFAULT_DEVELOPERS_FEE = 200;
    uint16 internal constant DEFAULT_OPERATORS_FEE = 0;
    uint16 internal constant DEFAULT_TREASURY_FEE = 800;

    // Missing member index
    uint256 internal constant MEMBER_NOT_FOUND = type(uint256).max;

    // Spec manager role
    bytes32 internal constant ROLE_SPEC_MANAGER = keccak256("ROLE_SPEC_MANAGER");

    // Beacon manager role
    bytes32 internal constant ROLE_BEACON_MANAGER = keccak256("ROLE_BEACON_MANAGER");

    // Pause manager role
    bytes32 internal constant ROLE_PAUSE_MANAGER = keccak256("ROLE_PAUSE_MANAGER");

    // Fee manager role
    bytes32 internal constant ROLE_FEE_MANAGER = keccak256("ROLE_FEE_MANAGER");

    // Ledger manager role
    bytes32 internal constant ROLE_LEDGER_MANAGER = keccak256("ROLE_LEDGER_MANAGER");

    // Stake manager role
    bytes32 internal constant ROLE_STAKE_MANAGER = keccak256("ROLE_STAKE_MANAGER");

    // Treasury manager role
    bytes32 internal constant ROLE_TREASURY = keccak256("ROLE_SET_TREASURY");

    // Developers address change role
    bytes32 internal constant ROLE_DEVELOPERS = keccak256("ROLE_SET_DEVELOPERS");

    // Token name
    string internal _name;

    // Token symbol
    string internal _symbol;

    // Token decimals
    uint8 internal _decimals;

    // Allow function calls only from member with specific role
    modifier auth(bytes32 role) {
        require(IAuthManager(AUTH_MANAGER).has(role, msg.sender), "LIDO: UNAUTHORIZED");
        _;
    }

    /**
     * @return the name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @return the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @return the number of decimals for getting user representation of a token amount.
     */
    function decimals() public view returns (uint8) {
        return _decimals;
    }

    /**
     * @notice setting token parameters
     */
    function setTokenInfo(string memory __name, string memory __symbol, uint8 __decimals) external {
        require(bytes(__name).length > 0, "LIDO: EMPTY_NAME");
        require(bytes(__symbol).length > 0, "LIDO: EMPTY_SYMBOL");
        require(__decimals > 0, "LIDO: ZERO_DECIMALS");
        require(bytes(_name).length == 0, "LIDO: NAME_SETTED");
        _name = __name;
        _symbol = __symbol;
        _decimals = __decimals;
    }

    /**
    * @notice Returns amount of total pooled tokens by contract.
    * @return amount of pooled vKSM in contract
    */
    function _getTotalPooledKSM() internal view override returns (uint256) {
        return fundRaisedBalance;
    }
}
