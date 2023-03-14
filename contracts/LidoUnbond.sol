// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../interfaces/IOracleMaster.sol";
import "../interfaces/ILedgerFactory.sol";
import "../interfaces/ILedger.sol";
import "../interfaces/IController.sol";
import "../interfaces/IAuthManager.sol";
import "../interfaces/IWithdrawal.sol";

import "./stKSM.sol";


contract LidoUnbond is stKSM, Initializable {
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

    // Flag indicating redeem availability
    bool private isRedeemEnabled;

    // Flag indicating if unbond is forced
    bool private isUnbondForced;

    // Allow function calls only from member with specific role
    modifier auth(bytes32 role) {
        require(IAuthManager(AUTH_MANAGER).has(role, msg.sender), "LIDO: UNAUTHORIZED");
        _;
    }

    // Allow call to redeem only when it's enabled
    modifier redeemEnabled() {
        require(isRedeemEnabled, "LIDO: REDEEM_DISABLED");
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
    // NOTE: function was removed from Lido, because it can be called only once to set parameters and after that
    // it is unnecessary in the code. It was removed to decrease contract bytecode size
    // function setTokenInfo(string memory __name, string memory __symbol, uint8 __decimals) external {
    //     require(bytes(__name).length > 0, "LIDO: EMPTY_NAME");
    //     require(bytes(__symbol).length > 0, "LIDO: EMPTY_SYMBOL");
    //     require(__decimals > 0, "LIDO: ZERO_DECIMALS");
    //     require(bytes(_name).length == 0, "LIDO: NAME_SETTED");
    //     _name = __name;
    //     _symbol = __symbol;
    //     _decimals = __decimals;
    // }

    /**
    * @notice Initialize lido contract.
    * @param _authManager - auth manager contract address
    * @param _vKSM - vKSM contract address
    * @param _controller - relay controller address
    * @param _developers - devs address
    * @param _treasury - treasury address
    * @param _oracleMaster - oracle master address
    * @param _withdrawal - withdrawal address
    * @param _depositCap - cap for deposits
    * @param _maxAllowableDifference - max allowable difference for oracle reports
    */
    function initialize(
        address _authManager,
        address _vKSM,
        address _controller,
        address _developers,
        address _treasury,
        address _oracleMaster,
        address _withdrawal,
        uint256 _depositCap,
        uint128 _maxAllowableDifference
    ) external initializer {
        require(_depositCap > 0, "LIDO: ZERO_CAP");
        require(_vKSM != address(0), "LIDO: INCORRECT_VKSM_ADDRESS");
        require(_oracleMaster != address(0), "LIDO: INCORRECT_ORACLE_MASTER_ADDRESS");
        require(_withdrawal != address(0), "LIDO: INCORRECT_WITHDRAWAL_ADDRESS");
        require(_authManager != address(0), "LIDO: INCORRECT_AUTHMANAGER_ADDRESS");
        require(_controller != address(0), "LIDO: INCORRECT_CONTROLLER_ADDRESS");

        VKSM = IERC20(_vKSM);
        CONTROLLER = _controller;
        AUTH_MANAGER = _authManager;

        depositCap = _depositCap;

        MAX_LEDGERS_AMOUNT = 200;
        Types.Fee memory _fee;
        _fee.total = DEFAULT_OPERATORS_FEE + DEFAULT_DEVELOPERS_FEE + DEFAULT_TREASURY_FEE;
        _fee.operators = DEFAULT_OPERATORS_FEE;
        _fee.developers = DEFAULT_DEVELOPERS_FEE;
        _fee.treasury = DEFAULT_TREASURY_FEE;
        FEE = _fee;

        treasury = _treasury;
        developers =_developers;

        ORACLE_MASTER = _oracleMaster;
        IOracleMaster(ORACLE_MASTER).setLido(address(this));

        WITHDRAWAL = _withdrawal;
        IWithdrawal(WITHDRAWAL).setStKSM(address(this));

        MAX_ALLOWABLE_DIFFERENCE = _maxAllowableDifference;
    }

    /**
    * @notice Set treasury address to '_treasury'
    */
    function setTreasury(address _treasury) external auth(ROLE_TREASURY) {
        require(_treasury != address(0), "LIDO: INCORRECT_TREASURY_ADDRESS");
        treasury = _treasury;
    }

    /**
    * @notice Set deposit cap to new value
    */
    function setDepositCap(uint256 _depositCap) external auth(ROLE_PAUSE_MANAGER) {
        require(_depositCap > 0, "LIDO: INCORRECT_NEW_CAP");
        depositCap = _depositCap;
    }

    /**
    * @notice Set ledger beacon address to '_ledgerBeacon'
    */
    function setLedgerBeacon(address _ledgerBeacon) external auth(ROLE_BEACON_MANAGER) {
        require(_ledgerBeacon != address(0), "LIDO: INCORRECT_BEACON_ADDRESS");
        LEDGER_BEACON = _ledgerBeacon;
    }

    function setMaxAllowableDifference(uint128 _maxAllowableDifference) external auth(ROLE_BEACON_MANAGER) {
        require(_maxAllowableDifference > 0, "LIDO: INCORRECT_MAX_ALLOWABLE_DIFFERENCE");
        MAX_ALLOWABLE_DIFFERENCE = _maxAllowableDifference;
    }

    /**
    * @notice Set ledger factory address to '_ledgerFactory'
    */
    function setLedgerFactory(address _ledgerFactory) external auth(ROLE_BEACON_MANAGER) {
        require(_ledgerFactory != address(0), "LIDO: INCORRECT_FACTORY_ADDRESS");
        LEDGER_FACTORY = _ledgerFactory;
    }

    /**
    * @notice Set developers address to '_developers'
    */
    function setDevelopers(address _developers) external auth(ROLE_DEVELOPERS) {
        require(_developers != address(0), "LIDO: INCORRECT_DEVELOPERS_ADDRESS");
        developers = _developers;
    }

    /**
    * @notice Set relay chain spec, allowed to call only by ROLE_SPEC_MANAGER
    * @dev if some params are changed function will iterate over oracles and ledgers, be careful
    * @param _relaySpec - new relaychain spec
    */
    function setRelaySpec(Types.RelaySpec calldata _relaySpec) external auth(ROLE_SPEC_MANAGER) {
        require(_relaySpec.maxValidatorsPerLedger > 0, "LIDO: BAD_MAX_VALIDATORS_PER_LEDGER");
        require(_relaySpec.maxUnlockingChunks > 0, "LIDO: BAD_MAX_UNLOCKING_CHUNKS");

        RELAY_SPEC = _relaySpec;

        _updateLedgerRelaySpecs(_relaySpec.minNominatorBalance, _relaySpec.ledgerMinimumActiveBalance, _relaySpec.maxUnlockingChunks);
    }

    /**
    * @notice Set new lido fee, allowed to call only by ROLE_FEE_MANAGER
    * @param _feeOperators - Operators percentage in basis points. It's always 3%
    * @param _feeTreasury - Treasury fund percentage in basis points
    * @param _feeDevelopers - Developers percentage in basis points
    */
    function setFee(uint16 _feeOperators, uint16 _feeTreasury,  uint16 _feeDevelopers) external auth(ROLE_FEE_MANAGER) {
        Types.Fee memory _fee;
        _fee.total = _feeTreasury + _feeOperators + _feeDevelopers;
        require(_fee.total <= 10000 && (_feeTreasury > 0 || _feeDevelopers > 0) && _feeOperators < 10000, "LIDO: FEE_DONT_ADD_UP");

        emit FeeSet(_fee.total, _feeOperators, _feeTreasury, _feeDevelopers);

        _fee.developers = _feeDevelopers;
        _fee.operators = _feeOperators;
        _fee.treasury = _feeTreasury;
        FEE = _fee;
    }

    /**
    * @notice Sets isRedeemEnabled flag, allowed to call only by ROLE_BEACON_MANAGER
    * @param _isRedeemEnabled - new value for the isRedeemEnabled flag
    */
    function setIsRedeemEnabled(bool _isRedeemEnabled) external auth(ROLE_BEACON_MANAGER) {
        isRedeemEnabled = _isRedeemEnabled;
    }

    /**
    * @notice Sets bufferedRedeems value in a forced manner, allowed to call only by ROLE_BEACON_MANAGER
    * @dev used to start forced unbond proccess by assigning bufferedRedeems with
    *      the value of the fundRaisedBalance
    * @param _bufferedRedeems - new bufferedRedeems value
    */
    function setBufferedRedeems(uint256 _bufferedRedeems) external auth(ROLE_BEACON_MANAGER) {
        require(!isRedeemEnabled, "LIDO: REDEEM_ENABLED");
        require(_bufferedRedeems <= fundRaisedBalance, "LIDO: VALUE_TOO_BIG");
        bufferedRedeems = _bufferedRedeems;
    }

    /**
    * @notice Sets isUnbondForced flag, allowed to call only by ROLE_BEACON_MANAGER
    * @dev used to indicate the start of the forced unbond proccess
    * @param _isUnbondForced - new isUnbondForced value
    */
    function setIsUnbondForced(bool _isUnbondForced) external auth(ROLE_BEACON_MANAGER) {
        require(!isRedeemEnabled, "LIDO: REDEEM_ENABLED");
        isUnbondForced = _isUnbondForced;
    }

    /**
    * @notice Return unbonded tokens amount for user
    * @param _holder - user account for whom need to calculate unbonding
    * @return waiting - amount of tokens which are not unbonded yet
    * @return unbonded - amount of token which unbonded and ready to claim
    */
    function getUnbonded(address _holder) external view returns (uint256 waiting, uint256 unbonded) {
        return IWithdrawal(WITHDRAWAL).getRedeemStatus(_holder);
    }

    /**
    * @notice Return relay chain stash account addresses
    * @return Array of bytes32 relaychain stash accounts
    */
    function getStashAccounts() public view returns (bytes32[] memory) {
        bytes32[] memory _stashes = new bytes32[](enabledLedgers.length + disabledLedgers.length);

        for (uint i = 0; i < enabledLedgers.length + disabledLedgers.length; i++) {
            address ledgerAddr = i < enabledLedgers.length ?
                enabledLedgers[i] : disabledLedgers[i - enabledLedgers.length];

            _stashes[i] = bytes32(ILedger(ledgerAddr).stashAccount());
        }

        return _stashes;
    }

    /**
    * @notice Return ledger contract addresses
    * @dev Each ledger contract linked with single stash account on the relaychain side
    * @return Array of ledger contract addresses
    */
    function getLedgerAddresses() public view returns (address[] memory) {
        address[] memory _ledgers = new address[](enabledLedgers.length + disabledLedgers.length);

        for (uint i = 0; i < enabledLedgers.length + disabledLedgers.length; i++) {
            _ledgers[i] = i < enabledLedgers.length ?
                enabledLedgers[i] : disabledLedgers[i - enabledLedgers.length];
        }

        return _ledgers;
    }

    /**
    * @notice Return ledger address by stash account id
    * @dev If ledger not found function returns ZERO address
    * @param _stashAccount - relaychain stash account id
    * @return Linked ledger contract address
    */
    function findLedger(bytes32 _stashAccount) external view returns (address) {
        return ledgerByStash[_stashAccount];
    }

    /**
    * @notice Stop pool routine operations (deposit, redeem, claimUnbonded),
    *         allowed to call only by ROLE_PAUSE_MANAGER
    */
    function pause() external auth(ROLE_PAUSE_MANAGER) {
        _pause();
    }

    /**
    * @notice Resume pool routine operations (deposit, redeem, claimUnbonded),
    *         allowed to call only by ROLE_PAUSE_MANAGER
    */
    function resume() external auth(ROLE_PAUSE_MANAGER) {
        _unpause();
    }

    /**
    * @notice Add new ledger, allowed to call only by ROLE_LEDGER_MANAGER
    * @dev That function deploys new ledger for provided stash account
    *      Also method triggers rebalancing stakes accross ledgers,
           recommended to carefully calculate share value to avoid significant rebalancing.
    * @param _stashAccount - relaychain stash account id
    * @param _controllerAccount - controller account id for given stash
    * @return created ledger address
    */
    function addLedger(
        bytes32 _stashAccount,
        bytes32 _controllerAccount,
        uint16 _index
    )
        external
        auth(ROLE_LEDGER_MANAGER)
        returns(address)
    {
        require(LEDGER_BEACON != address(0), "LIDO: UNSPECIFIED_LEDGER_BEACON");
        require(LEDGER_FACTORY != address(0), "LIDO: UNSPECIFIED_LEDGER_FACTORY");
        require(ORACLE_MASTER != address(0), "LIDO: NO_ORACLE_MASTER");
        require(enabledLedgers.length + disabledLedgers.length < MAX_LEDGERS_AMOUNT, "LIDO: LEDGERS_POOL_LIMIT");
        require(ledgerByStash[_stashAccount] == address(0), "LIDO: STASH_ALREADY_EXISTS");

        address ledger = ILedgerFactory(LEDGER_FACTORY).createLedger(
            _stashAccount,
            _controllerAccount,
            address(VKSM),
            CONTROLLER,
            RELAY_SPEC.minNominatorBalance,
            RELAY_SPEC.ledgerMinimumActiveBalance,
            RELAY_SPEC.maxUnlockingChunks
        );

        enabledLedgers.push(ledger);
        ledgerByStash[_stashAccount] = ledger;
        ledgerByAddress[ledger] = true;

        IOracleMaster(ORACLE_MASTER).addLedger(ledger);

        IController(CONTROLLER).newSubAccount(_index, _stashAccount, ledger);

        emit LedgerAdd(ledger, _stashAccount, _controllerAccount);
        return ledger;
    }

    /**
    * @notice Disable ledger, allowed to call only by ROLE_LEDGER_MANAGER
    * @dev That method put ledger to "draining" mode, after ledger drained it can be removed
    * @param _ledgerAddress - target ledger address
    */
    function disableLedger(address _ledgerAddress) external auth(ROLE_LEDGER_MANAGER) {
        _disableLedger(_ledgerAddress);
    }

    /**
    * @notice Disable ledger and pause all redeems for that ledger, allowed to call only by ROLE_LEDGER_MANAGER
    * @dev That method pause all stake changes for ledger
    * @param _ledgerAddress - target ledger address
    */
    function emergencyPauseLedger(address _ledgerAddress) external auth(ROLE_LEDGER_MANAGER) {
        _disableLedger(_ledgerAddress);
        pausedledgers[_ledgerAddress] = true;
        emit LedgerPaused(_ledgerAddress);
    }

    /**
    * @notice Allow redeems from paused ledger, allowed to call only by ROLE_LEDGER_MANAGER
    * @param _ledgerAddress - target ledger address
    */
    function resumeLedger(address _ledgerAddress) external auth(ROLE_LEDGER_MANAGER) {
        require(pausedledgers[_ledgerAddress], "LIDO: LEDGER_NOT_PAUSED");
        delete pausedledgers[_ledgerAddress];
        emit LedgerResumed(_ledgerAddress);
    }

    /**
    * @notice Remove ledger, allowed to call only by ROLE_LEDGER_MANAGER
    * @dev That method cannot be executed for running ledger, so need to drain funds
    * @param _ledgerAddress - target ledger address
    */
    function removeLedger(address _ledgerAddress) external auth(ROLE_LEDGER_MANAGER) {
        require(ledgerByAddress[_ledgerAddress], "LIDO: LEDGER_NOT_FOUND");
        require(ledgerStake[_ledgerAddress] == 0, "LIDO: LEDGER_HAS_NON_ZERO_STAKE");
        // uint256 ledgerIdx = _findDisabledLedger(_ledgerAddress);
        uint256 ledgerIdx = _findLedger(_ledgerAddress, false);
        require(ledgerIdx != type(uint256).max, "LIDO: LEDGER_NOT_DISABLED");

        ILedger ledger = ILedger(_ledgerAddress);
        require(ledger.isEmpty(), "LIDO: LEDGER_IS_NOT_EMPTY");

        address lastLedger = disabledLedgers[disabledLedgers.length - 1];
        disabledLedgers[ledgerIdx] = lastLedger;
        disabledLedgers.pop();

        delete ledgerByAddress[_ledgerAddress];
        delete ledgerByStash[ledger.stashAccount()];

        if (pausedledgers[_ledgerAddress]) {
            delete pausedledgers[_ledgerAddress];
        }

        IOracleMaster(ORACLE_MASTER).removeLedger(_ledgerAddress);

        IController(CONTROLLER).deleteSubAccount(_ledgerAddress);

        emit LedgerRemove(_ledgerAddress);
    }

    /**
    * @notice Nominate on behalf of gived array of stash accounts, allowed to call only by ROLE_STAKE_MANAGER
    * @dev Method spawns xcm call to relaychain
    * @param _stashAccounts - target stash accounts id
    * @param _validators - validators set to be nominated
    */
    function nominateBatch(bytes32[] calldata _stashAccounts, bytes32[][] calldata _validators) external auth(ROLE_STAKE_MANAGER) {
        require(_stashAccounts.length == _validators.length, "LIDO: INCORRECT_INPUT");

        for (uint256 i = 0; i < _stashAccounts.length; ++i) {
            require(ledgerByStash[_stashAccounts[i]] != address(0),  "LIDO: UNKNOWN_STASH_ACCOUNT");

            require(_validators[i].length <= RELAY_SPEC.maxValidatorsPerLedger, "LIDO: VALIDATORS_AMOUNT_TOO_BIG");

            ILedger(ledgerByStash[_stashAccounts[i]]).nominate(_validators[i]);
        }
    }

    function deposit(uint256 _amount) external returns (uint256) {
        return _deposit(_amount);
    }

    function deposit(uint256 _amount, address _referral) external returns (uint256) {
        uint256 shares = _deposit(_amount);
        emit Referral(msg.sender, _referral, _amount, shares);
        return shares;
    }

    /**
    * @notice Deposit vKSM tokens to the pool and recieve stKSM(liquid staked tokens) instead.
              User should approve tokens before executing this call.
    * @dev Method accoumulate vKSMs on contract
    * @param _amount - amount of vKSM tokens to be deposited
    */
    function _deposit(uint256 _amount) internal whenNotPaused returns (uint256) {
        require(fundRaisedBalance + _amount < depositCap, "LIDO: DEPOSITS_EXCEED_CAP");

        VKSM.transferFrom(msg.sender, address(this), _amount);

        require(_amount != 0, "LIDO: ZERO_DEPOSIT");

        uint256 shares = getSharesByPooledKSM(_amount);
        if (shares == 0) {
            // totalPooledKSM is 0: either the first-ever deposit or complete slashing
            // assume that shares correspond to KSM as 1-to-1
            shares = _amount;
        }

        fundRaisedBalance += _amount;
        bufferedDeposits += _amount;
        _mintShares(msg.sender, shares);

        _emitTransferAfterMintingShares(msg.sender, shares);

        emit Deposited(msg.sender, _amount);

        return shares;
    }

    /**
    * @notice Create request to redeem vKSM in exchange of stKSM. stKSM will be instantly burned and
              created claim order, (see `getUnbonded` method).
              User can have up to 20 redeem requests in parallel.
    * @param _amount - amount of stKSM tokens to be redeemed
    */
    function redeem(uint256 _amount) external whenNotPaused redeemEnabled {
        uint256 _shares = getSharesByPooledKSM(_amount);
        require(_shares > 0, "LIDO: AMOUNT_TOO_LOW");
        require(_shares <= _sharesOf(msg.sender), "LIDO: REDEEM_AMOUNT_EXCEEDS_BALANCE");

        _burnShares(msg.sender, _shares);
        fundRaisedBalance -= _amount;
        bufferedRedeems += _amount;

        IWithdrawal(WITHDRAWAL).redeem(msg.sender, _amount);

        // emit event about burning (compatible with ERC20)
        emit Transfer(msg.sender, address(0), _amount);

        // lido event about redeemed
        emit Redeemed(msg.sender, _amount);
    }

    /**
    * @notice Claim all unbonded tokens at this point of time. Executed redeem requests will be removed
              and approproate amount of vKSM transferred to calling account.
    */
    function claimUnbonded() external whenNotPaused {
        uint256 amount = IWithdrawal(WITHDRAWAL).claim(msg.sender);
        emit Claimed(msg.sender, amount);
    }

    /**
    * @notice Claim all vKSM tokens which were forcefully unbonded. Burns stKSM shares
    */
    function claimForcefullyUnbonded() external whenNotPaused {
        require(isUnbondForced, "LIDO: UNBOND_NOT_FORCED");

        uint256 sharesToBurn = _sharesOf(msg.sender);
        require(sharesToBurn > 0, "LIDO: NOTHING_TO_CLAIM");

        uint256 tokensToClaim = getPooledKSMByShares(sharesToBurn);
        fundRaisedBalance -= tokensToClaim;

        _burnShares(msg.sender, sharesToBurn);
        IWithdrawal(WITHDRAWAL).claimForcefullyUnbonded(msg.sender, tokensToClaim);
        emit Claimed(msg.sender, tokensToClaim);
    }

    /**
    * @notice Distribute rewards earned by ledger, allowed to call only by ledger
    */
    function distributeRewards(uint256 _totalRewards, uint256 _ledgerBalance) external {
        require(ledgerByAddress[msg.sender], "LIDO: NOT_FROM_LEDGER");

        Types.Fee memory _fee = FEE;

        // it's `feeDevelopers` + `feeTreasure`
        uint256 _feeDevTreasure = uint256(_fee.developers + _fee.treasury);
        assert(_feeDevTreasure>0);

        fundRaisedBalance += _totalRewards;
        ledgerStake[msg.sender] += _totalRewards;
        ledgerBorrow[msg.sender] += _totalRewards;

        uint256 _rewards = _totalRewards * _feeDevTreasure / uint256(10000 - _fee.operators);
        uint256 denom = _getTotalPooledKSM()  - _rewards;
        uint256 shares2mint = _getTotalPooledKSM();
        if (denom > 0) shares2mint = _rewards * _getTotalShares() / denom;

        _mintShares(treasury, shares2mint);

        uint256 _devShares = shares2mint *  uint256(_fee.developers) / _feeDevTreasure;
        _transferShares(treasury, developers, _devShares);
        _emitTransferAfterMintingShares(developers, _devShares);
        _emitTransferAfterMintingShares(treasury, shares2mint - _devShares);

        emit Rewards(msg.sender, _totalRewards, _ledgerBalance);
    }

    /**
    * @notice Distribute lossed by ledger, allowed to call only by ledger
    */
    function distributeLosses(uint256 _totalLosses, uint256 _ledgerBalance) external {
        require(ledgerByAddress[msg.sender], "LIDO: NOT_FROM_LEDGER");

        uint256 withdrawalBalance = IWithdrawal(WITHDRAWAL).totalBalanceForLosses();
        uint256 withdrawalPendingForClaiming = IWithdrawal(WITHDRAWAL).pendingForClaiming();
        uint256 withdrawalVKSMBalance = VKSM.balanceOf(WITHDRAWAL);
        // NOTE: VKSM balance that was "fasttracked" to Withdrawal can't receive slash
        uint256 virtualWithdrawalBalance = 0;
        if (withdrawalBalance + withdrawalPendingForClaiming > withdrawalVKSMBalance) {
            // NOTE: protection from ddos
            virtualWithdrawalBalance =
                withdrawalBalance - (withdrawalVKSMBalance - withdrawalPendingForClaiming);
        }

        // lidoPart = _totalLosses * lido_xcKSM_balance / sum_xcKSM_balance
        uint256 lidoPart = (_totalLosses * fundRaisedBalance) / (fundRaisedBalance + virtualWithdrawalBalance);

        fundRaisedBalance -= lidoPart;
        if ((_totalLosses - lidoPart) > 0) {
            IWithdrawal(WITHDRAWAL).ditributeLosses(_totalLosses - lidoPart);
        }

        // edge case when loss can be more than stake
        ledgerStake[msg.sender] -= ledgerStake[msg.sender] >= lidoPart ? lidoPart : ledgerStake[msg.sender];
        ledgerBorrow[msg.sender] -= _totalLosses;

        emit Losses(msg.sender, _totalLosses, _ledgerBalance);
    }

    /**
    * @notice Transfer vKSM from ledger to LIDO. Can be called only from ledger
    * @param _amount - amount of vKSM that should be transfered
    * @param _excess - excess of vKSM that was transfered
    */
    function transferFromLedger(uint256 _amount, uint256 _excess) external {
        require(ledgerByAddress[msg.sender], "LIDO: NOT_FROM_LEDGER");

        if (_excess > 0) { // some donations
            fundRaisedBalance += _excess; //just distribute it as rewards
            bufferedDeposits += _excess;
            VKSM.transferFrom(msg.sender, address(this), _excess);
        }

        ledgerBorrow[msg.sender] -= _amount;
        VKSM.transferFrom(msg.sender, WITHDRAWAL, _amount);
    }

    /**
    * @notice Transfer vKSM from LIDO to ledger. Can be called only from ledger
    * @param _amount - amount of transfered vKSM
    */
    function transferToLedger(uint256 _amount) external {
        require(ledgerByAddress[msg.sender], "LIDO: NOT_FROM_LEDGER");
        require(ledgerBorrow[msg.sender] + _amount <= ledgerStake[msg.sender], "LIDO: LEDGER_NOT_ENOUGH_STAKE");

        ledgerBorrow[msg.sender] += _amount;
        VKSM.transfer(msg.sender, _amount);
    }

    /**
    * @notice Flush stakes, allowed to call only by oracle master
    * @dev This method distributes buffered stakes between ledgers by soft manner
    */
    function flushStakes() external {
        require(msg.sender == ORACLE_MASTER, "LIDO: NOT_FROM_ORACLE_MASTER");

        IWithdrawal(WITHDRAWAL).newEra();
        _softRebalanceStakes();
    }

    /**
    * @notice Rebalance stake accross ledgers by soft manner.
    */
    function _softRebalanceStakes() internal {
        uint256 totalStakeExcess = 0;
        for (uint256 i = 0; i < enabledLedgers.length + disabledLedgers.length; ++i) {
            address ledgerAddr = i < enabledLedgers.length ?
                enabledLedgers[i] : disabledLedgers[i - enabledLedgers.length];

            // consider an incorrect case when our records about the ledger are wrong:
            // the ledger's active stake > the ledger's total amount of funds
            if (ledgerStake[ledgerAddr] > ledgerBorrow[ledgerAddr]) {

                uint256 ledgerStakeExcess = ledgerStake[ledgerAddr] - ledgerBorrow[ledgerAddr];

                // new total stake excess <= the amount of funds that won't be sent to the ledgers
                if (totalStakeExcess + ledgerStakeExcess <= VKSM.balanceOf(address(this)) - bufferedDeposits) {
                    totalStakeExcess += ledgerStakeExcess;

                    // correcting the ledger's active stake record
                    ledgerStake[ledgerAddr] -= ledgerStakeExcess;
                }
            }
        }

        // the amount of funds to be sent to the ledgers should decrease the ledgers' stake excess
        bufferedDeposits += totalStakeExcess;

        if (bufferedDeposits > 0 || bufferedRedeems > 0) {
            // first try to distribute redeems accross disabled ledgers
            if (disabledLedgers.length > 0 && bufferedRedeems > 0) {
                bufferedRedeems = _processDisabledLedgers(bufferedRedeems);
            }

            // NOTE: if we have deposits and redeems in one era we need to send all possible xcKSMs to Withdrawal
            if (bufferedDeposits > 0 && bufferedRedeems > 0) {
                uint256 maxImmediateTransfer = bufferedDeposits > bufferedRedeems ? bufferedRedeems : bufferedDeposits;
                bufferedDeposits -= maxImmediateTransfer;
                bufferedRedeems -= maxImmediateTransfer;
                VKSM.transfer(WITHDRAWAL, maxImmediateTransfer);
            }

            // distribute remaining stakes and redeems accross enabled
            if (enabledLedgers.length > 0) {
                int256 stake = bufferedDeposits.toInt256() - bufferedRedeems.toInt256();
                if (stake != 0) {
                    _processEnabled(stake);
                }
                bufferedDeposits = 0;
                bufferedRedeems = 0;
            }
        }
    }

    /**
    * @notice Spread redeems accross disabled ledgers
    * @return remainingRedeems - redeems amount which didn't distributed
    */
    function _processDisabledLedgers(uint256 redeems) internal returns(uint256 remainingRedeems) {
        uint256 disabledLength = disabledLedgers.length;
        assert(disabledLength > 0);

        uint256 stakesSum = 0;
        uint256 actualRedeems = 0;

        for (uint256 i = 0; i < disabledLength; ++i) {
            if (!pausedledgers[disabledLedgers[i]]) {
                stakesSum += ledgerStake[disabledLedgers[i]];
            }
        }

        if (stakesSum == 0) return redeems;

        for (uint256 i = 0; i < disabledLength; ++i) {
            if (!pausedledgers[disabledLedgers[i]]) {
                uint256 currentStake = ledgerStake[disabledLedgers[i]];
                uint256 decrement = redeems * currentStake / stakesSum;
                decrement = decrement > currentStake ? currentStake : decrement;
                ledgerStake[disabledLedgers[i]] = currentStake - decrement;
                actualRedeems += decrement;
            }
        }

        return redeems - actualRedeems;
    }

    /**
    * @notice Distribute stakes and redeems accross enabled ledgers with relaxation
    * @dev this function should never mix bond/unbond
    */
    function _processEnabled(int256 _stake) internal {
        uint256 ledgersLength = enabledLedgers.length;
        assert(ledgersLength > 0);

        int256[] memory diffs = new int256[](ledgersLength);
        address[] memory ledgersCache = new address[](ledgersLength);
        int256[] memory ledgerStakesCache = new int256[](ledgersLength);
        // NOTE: cache can't be used, because it can be changed or not in algorithm
        uint256[] memory ledgerStakePrevious = new uint256[](ledgersLength);

        int256 activeDiffsSum = 0;
        int256 totalChange = 0;
        int256 preciseDiffSum = 0;
        uint256 targetStake = 0;

        {
            if (!isUnbondForced && isRedeemEnabled && bufferedRedeems != fundRaisedBalance) {
                targetStake = getTotalPooledKSM() / ledgersLength;
            }
            int256 diff = 0;
            for (uint256 i = 0; i < ledgersLength; ++i) {
                ledgersCache[i] = enabledLedgers[i];
                ledgerStakesCache[i] = int256(ledgerStake[ledgersCache[i]]);
                ledgerStakePrevious[i] = ledgerStake[ledgersCache[i]];

                diff = int256(targetStake) - int256(ledgerStakesCache[i]);
                if (_stake * diff > 0) {
                    activeDiffsSum += diff;
                }
                diffs[i] = diff;
                preciseDiffSum += diff;
            }
        }

        if (preciseDiffSum == 0 || activeDiffsSum == 0) {
            return;
        }

        int8 direction = 1;
        if (activeDiffsSum < 0) {
            direction = -1;
            activeDiffsSum = -activeDiffsSum;
        }

        for (uint256 i = 0; i < ledgersLength; ++i) {
            diffs[i] *= direction;
            if (diffs[i] > 0) {
                int256 change = diffs[i] * _stake / activeDiffsSum;
                int256 newStake = ledgerStakesCache[i] + change;
                ledgerStake[ledgersCache[i]] = uint256(newStake);
                ledgerStakesCache[i] = newStake;
                totalChange += change;
            }
        }

        {
            int256 remaining = _stake - totalChange;
            if (remaining > 0) {
                // just add to first ledger
                ledgerStake[ledgersCache[0]] += uint256(remaining);
            }
            else if (remaining < 0) {
                for (uint256 i = 0; i < ledgersLength && remaining < 0; ++i) {
                    uint256 stake = uint256(ledgerStakesCache[i]);
                    if (stake > 0) {
                        uint256 decrement = stake > uint256(-remaining) ? uint256(-remaining) : stake;
                        ledgerStake[ledgersCache[i]] -= decrement;
                        remaining += int256(decrement);
                    }
                }
            }
        }

        // NOTE: this check used to catch cases when one user redeem some funds and another deposit in next era
        // so ledgers stake would increase and they return less xcKSMs and remaining funds would be locked on Lido
        uint256 freeToTransferFunds = 0;
        for (uint256 i = 0; i < ledgersLength; ++i) {
            // NOTE: protection from double sending of funds
            uint256 updatedLedgerBorrow = ledgerBorrow[ledgersCache[i]] - uint256(ILedger(ledgersCache[i]).transferDownwardBalance());
            if (
                // NOTE: this means that we wait transfer from ledger
                updatedLedgerBorrow > ledgerStakePrevious[i] &&
                // NOTE: and new deposits increase ledger stake
                ledgerStake[ledgersCache[i]] > ledgerStakePrevious[i]
                ) {
                    freeToTransferFunds +=
                        ledgerStake[ledgersCache[i]] > updatedLedgerBorrow ?
                        updatedLedgerBorrow - ledgerStakePrevious[i] :
                        ledgerStake[ledgersCache[i]] - ledgerStakePrevious[i];
            }
        }

        if (freeToTransferFunds > 0) {
            VKSM.transfer(WITHDRAWAL, uint256(freeToTransferFunds));
        }
    }

    /**
    * @notice Set new minimum balance for ledger
    * @param _minNominatorBalance - new minimum nominator balance
    * @param _minimumBalance - new minimum active balance for ledger
    * @param _maxUnlockingChunks - new maximum unlocking chunks
    */
    function _updateLedgerRelaySpecs(uint128 _minNominatorBalance, uint128 _minimumBalance, uint256 _maxUnlockingChunks) internal {
        for (uint i = 0; i < enabledLedgers.length + disabledLedgers.length; i++) {
            address ledgerAddress = i < enabledLedgers.length ?
                enabledLedgers[i] : disabledLedgers[i - enabledLedgers.length];
            ILedger(ledgerAddress).setRelaySpecs(_minNominatorBalance, _minimumBalance, _maxUnlockingChunks);
        }
    }

    /**
    * @notice Disable ledger
    * @dev That method put ledger to "draining" mode, after ledger drained it can be removed
    * @param _ledgerAddress - target ledger address
    */
    function _disableLedger(address _ledgerAddress) internal {
        require(ledgerByAddress[_ledgerAddress], "LIDO: LEDGER_NOT_FOUND");
        uint256 ledgerIdx = _findLedger(_ledgerAddress, true);
        require(ledgerIdx != type(uint256).max, "LIDO: LEDGER_NOT_ENABLED");

        address lastLedger = enabledLedgers[enabledLedgers.length - 1];
        enabledLedgers[ledgerIdx] = lastLedger;
        enabledLedgers.pop();

        disabledLedgers.push(_ledgerAddress);

        emit LedgerDisable(_ledgerAddress);
    }

    /**
    * @notice Emits an {Transfer} event where from is 0 address. Indicates mint events.
    */
    function _emitTransferAfterMintingShares(address _to, uint256 _sharesAmount) internal {
        emit Transfer(address(0), _to, getPooledKSMByShares(_sharesAmount));
    }

    /**
    * @notice Returns amount of total pooled tokens by contract.
    * @return amount of pooled vKSM in contract
    */
    function _getTotalPooledKSM() internal view override returns (uint256) {
        return fundRaisedBalance;
    }

    /**
    * @notice Returns enabled or disabled ledger index by given address
    * @return enabled or disabled ledger index or uint256_max if not found
    */
    function _findLedger(address _ledgerAddress, bool _enabled) internal view returns(uint256) {
        uint256 length = _enabled ? enabledLedgers.length : disabledLedgers.length;
        for (uint256 i = 0; i < length; ++i) {
            address ledgerAddress = _enabled ? enabledLedgers[i] : disabledLedgers[i];
            if (ledgerAddress == _ledgerAddress) {
                return i;
            }
        }
        return type(uint256).max;
    }
}
