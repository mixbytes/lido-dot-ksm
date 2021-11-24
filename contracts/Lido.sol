// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../interfaces/IOracleMaster.sol";
import "../interfaces/ILedger.sol";
import "../interfaces/IController.sol";
import "../interfaces/IAuthManager.sol";

import "./stKSM.sol";


contract Lido is stKSM, Initializable {
    using Clones for address;
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

    // Rewards distributed
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

    // Ledger removed
    event LedgerDisable(
        address addr
    );

    // sum of all deposits and rewards
    uint256 private fundRaisedBalance;

    struct Claim {
        uint256 balance;
        uint64 timeout;
    }
    // one claim for account
    mapping(address => Claim[]) public claimOrders;

    // pending claims total
    uint256 public pendingClaimsTotal;

    // Ledger address by stash account id
    mapping(bytes32 => address) private ledgerByStash;

    // Map to check ledger existence by address
    mapping(address => bool) private ledgerByAddress;

    // haven't executed buffrered deposits
    uint256 public bufferedDeposits;

    // haven't executed buffrered redeems
    uint256 public bufferedRedeems;

    // Ledger stakes
    mapping(address => uint256) public ledgerStake;

    // Disabled ledgers
    address[] public disabledLedgers;

    // Enabled ledgers
    address[] public enabledLedgers;

    // vKSM precompile
    IERC20 public vKSM;
    // controller
    address public controller;


    // auth manager contract address
    address public AUTH_MANAGER;

    // Maximum number of ledgers
    uint256 public MAX_LEDGERS_AMOUNT;

    /** fee interest in basis points.
    It's packed uint256 consist of three uint16 (total_fee, treasury_fee, developers_fee).
    where total_fee = treasury_fee + developers_fee + 3000 (3% operators fee)
    */
    Types.Fee private FEE;

    // ledger clone template contract
    address public LEDGER_CLONE;

    // oracle master contract
    address public ORACLE_MASTER;

    // relay spec
    Types.RelaySpec public RELAY_SPEC;

    // developers fund
    address public developers;

    // treasury fund
    address public treasury;

    /** default interest value in base points.
    */
    uint16 internal constant DEFAULT_DEVELOPERS_FEE = 140;
    uint16 internal constant DEFAULT_OPERATORS_FEE = 300;
    uint16 internal constant DEFAULT_TREASURY_FEE = 560;

    // Missing member index
    uint256 internal constant MEMBER_NOT_FOUND = type(uint256).max;

    // Spec manager role
    bytes32 internal constant ROLE_SPEC_MANAGER = keccak256("ROLE_SPEC_MANAGER");

    // Pause manager role
    bytes32 internal constant ROLE_PAUSE_MANAGER = keccak256("ROLE_PAUSE_MANAGER");

    // Fee manager role
    bytes32 internal constant ROLE_FEE_MANAGER = keccak256("ROLE_FEE_MANAGER");

    // Oracle manager role
    bytes32 internal constant ROLE_ORACLE_MANAGER = keccak256("ROLE_ORACLE_MANAGER");

    // Ledger manager role
    bytes32 internal constant ROLE_LEDGER_MANAGER = keccak256("ROLE_LEDGER_MANAGER");

    // Stake manager role
    bytes32 internal constant ROLE_STAKE_MANAGER = keccak256("ROLE_STAKE_MANAGER");

    // Treasury manager role
    bytes32 internal constant ROLE_TREASURY = keccak256("ROLE_SET_TREASURY");

    // Developers address change role
    bytes32 internal constant ROLE_DEVELOPERS = keccak256("ROLE_SET_DEVELOPERS");

    // max amount of claims in parallel
    uint16 internal constant MAX_CLAIMS = 10;


    modifier auth(bytes32 role) {
        require(IAuthManager(AUTH_MANAGER).has(role, msg.sender), "LIDO: UNAUTHORIZED");
        _;
    }

    /**
    * @notice Initialize lido contract.
    * @param _authManager - auth manager contract address
    * @param _vKSM - vKSM contract address
    * @param _controller - relay controller address
    * @param _developers - devs address
    * @param _treasury - treasury address
    */
    function initialize(
        address _authManager,
        address _vKSM,
        address _controller,
        address _developers,
        address _treasury
    ) external initializer {
        vKSM = IERC20(_vKSM);
        controller = _controller;
        AUTH_MANAGER = _authManager;

        MAX_LEDGERS_AMOUNT = 200;
        Types.Fee memory _fee;
        _fee.total = DEFAULT_OPERATORS_FEE + DEFAULT_DEVELOPERS_FEE + DEFAULT_TREASURY_FEE;
        _fee.operators = DEFAULT_OPERATORS_FEE;
        _fee.developers = DEFAULT_DEVELOPERS_FEE;
        _fee.treasury = DEFAULT_TREASURY_FEE;
        FEE = _fee;

        treasury = _treasury;
        developers =_developers;
    }

    /**
    * @notice Stub fallback for native token, always reverting
    */
    fallback() external {
        revert("FORBIDDEN");
    }

    /**
    * @notice Set treasury address to '_treasury'
    */
    function setTreasury(address _treasury) external auth(ROLE_TREASURY) {
        require(_treasury != address(0), "LIDO: INCORRECT_TREASURY_ADDRESS");
        treasury = _treasury;
    }

    /**
    * @notice Set developers address to '_developers'
    */
    function setDevelopers(address _developers) external auth(ROLE_DEVELOPERS) {
        require(_developers != address(0), "LIDO: INCORRECT_DEVELOPERS_ADDRESS");
        developers = _developers;
    }

    /**
    * @notice Return unbonded tokens amount for user
    * @param _holder - user account for whom need to calculate unbonding
    * @return waiting - amount of tokens which are not unbonded yet
    * @return unbonded - amount of token which unbonded and ready to claim
    */
    function getUnbonded(address _holder) external view returns (uint256 waiting, uint256 unbonded) {
        uint256 waitingToUnbonding = 0;
        uint256 readyToClaim = 0;
        Claim[] storage orders = claimOrders[_holder];

        for (uint256 i = 0; i < orders.length; ++i) {
            if (orders[i].timeout < block.timestamp) {
                readyToClaim += orders[i].balance;
            }
            else {
                waitingToUnbonding += orders[i].balance;
            }
        }
        return (waitingToUnbonding, readyToClaim);
    }

    /**
    * @notice Return relay chain stash account addresses
    * @return Array of bytes32 relaychain stash accounts
    */
    function getStashAccounts() public view returns (bytes32[] memory) {
        bytes32[] memory _stashes = new bytes32[](enabledLedgers.length + disabledLedgers.length);

        for (uint i = 0; i < enabledLedgers.length; i++) {
            _stashes[i] = bytes32(ILedger(enabledLedgers[i]).stashAccount());
        }

        for (uint i = 0; i < disabledLedgers.length; i++) {
            _stashes[enabledLedgers.length + i] = bytes32(ILedger(disabledLedgers[i]).stashAccount());
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

        for (uint i = 0; i < enabledLedgers.length; i++) {
            _ledgers[i] = enabledLedgers[i];
        }

        for (uint i = 0; i < disabledLedgers.length; i++) {
            _ledgers[enabledLedgers.length + i] = disabledLedgers[i];
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
    * @notice Return vKSM amount available for stake by ledger
    * @dev If we have balance less than pendingClaimsTotal that means
    *      that ledgers already have locked KSMs
    */
    function avaliableForStake() external view returns(uint256) {
        uint256 freeBalance = vKSM.balanceOf(address(this));
        return freeBalance < pendingClaimsTotal ? 0 : freeBalance - pendingClaimsTotal;
    }

    /**
    * @notice Set relay chain spec, allowed to call only by ROLE_SPEC_MANAGER
    * @dev if some params are changed function will iterate over oracles and ledgers, be careful
    * @param _relaySpec - new relaychain spec
    */
    function setRelaySpec(Types.RelaySpec calldata _relaySpec) external auth(ROLE_SPEC_MANAGER) {
        require(ORACLE_MASTER != address(0), "LIDO: ORACLE_MASTER_UNDEFINED");
        require(_relaySpec.genesisTimestamp > 0, "LIDO: BAD_GENESIS_TIMESTAMP");
        require(_relaySpec.secondsPerEra > 0, "LIDO: BAD_SECONDS_PER_ERA");
        require(_relaySpec.unbondingPeriod > 0, "LIDO: BAD_UNBONDING_PERIOD");
        require(_relaySpec.maxValidatorsPerLedger > 0, "LIDO: BAD_MAX_VALIDATORS_PER_LEDGER");

        //TODO loop through ledgerByAddress and oracles if some params changed

        RELAY_SPEC = _relaySpec;

        IOracleMaster(ORACLE_MASTER).setRelayParams(_relaySpec.genesisTimestamp, _relaySpec.secondsPerEra);
    }

    /**
    * @notice Set oracle master address, allowed to call only by ROLE_ORACLE_MANAGER and only once
    * @dev After setting non zero address it cannot be changed more
    * @param _oracleMaster - oracle master address
    */
    function setOracleMaster(address _oracleMaster) external auth(ROLE_ORACLE_MANAGER) {
        require(ORACLE_MASTER == address(0), "LIDO: ORACLE_MASTER_ALREADY_DEFINED");
        require(_oracleMaster != address(0), "LIDO: INCORRECT_ORACLE_MASTER_ADDRESS");
        ORACLE_MASTER = _oracleMaster;
        IOracleMaster(ORACLE_MASTER).setLido(address(this));
    }

    /**
    * @notice Set new ledger clone contract address, allowed to call only by ROLE_LEDGER_MANAGER
    * @dev After setting new ledger clone address, old ledgers won't be affected, be careful
    * @param _ledgerClone - ledger clone address
    */
    function setLedgerClone(address _ledgerClone) external auth(ROLE_LEDGER_MANAGER) {
        require(_ledgerClone != address(0), "LIDO: INCORRECT_LEDGER_CLONE_ADDRESS");
        LEDGER_CLONE = _ledgerClone;
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
        require(_fee.total <= 10000 && (_feeTreasury > 0 || _feeDevelopers > 0) , "LIDO: FEE_DONT_ADD_UP");

        emit FeeSet(_fee.total, _feeOperators, _feeTreasury, _feeDevelopers);

        _fee.developers = _feeDevelopers;
        _fee.operators = _feeOperators;
        _fee.treasury = _feeTreasury;
        FEE = _fee;
    }

    /**
    * @notice Returns total fee basis points
    */
    function getFee() external view returns (uint16){
        return FEE.total;
    }

    /**
    * @notice Returns operators fee basis points
    */
    function getOperatorsFee() external view returns (uint16){
        return FEE.operators;
    }

    /**
    * @notice Returns treasury fee basis points
    */
    function getTreasuryFee() external view returns (uint16){
       return FEE.treasury;
    }

    /**
    * @notice Returns developers fee basis points
    */
    function getDevelopersFee() external view returns (uint16){
        return FEE.developers;
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
        require(LEDGER_CLONE != address(0), "LIDO: UNSPECIFIED_LEDGER_CLONE");
        require(ORACLE_MASTER != address(0), "LIDO: NO_ORACLE_MASTER");
        require(enabledLedgers.length + disabledLedgers.length < MAX_LEDGERS_AMOUNT, "LIDO: LEDGERS_POOL_LIMIT");
        require(ledgerByStash[_stashAccount] == address(0), "LIDO: STASH_ALREADY_EXISTS");

        address ledger = LEDGER_CLONE.cloneDeterministic(_stashAccount);
        // skip one era before commissioning
        ILedger(ledger).initialize(
            _stashAccount,
            _controllerAccount,
            address(vKSM),
            controller,
            RELAY_SPEC.minNominatorBalance
        );
        enabledLedgers.push(ledger);
        ledgerByStash[_stashAccount] = ledger;
        ledgerByAddress[ledger] = true;

        IOracleMaster(ORACLE_MASTER).addLedger(ledger);

//        vKSM.approve(ledger, type(uint256).max);

        IController(controller).newSubAccount(_index, _stashAccount, ledger);

        emit LedgerAdd(ledger, _stashAccount, _controllerAccount);
        return ledger;
    }


    /**
    * @notice Remove ledger, allowed to call only by ROLE_LEDGER_MANAGER
    * @dev That method cannot be executed for running ledger, so need to drain funds
    * @param _ledgerAddress - target ledger address
    */
    function removeLedger(address _ledgerAddress) external auth(ROLE_LEDGER_MANAGER) {
        require(ledgerByAddress[_ledgerAddress], "LIDO: LEDGER_NOT_FOUND");
        require(ledgerStake[_ledgerAddress] == 0, "LIDO: LEDGER_HAS_NON_ZERO_STAKE");
        uint256 ledgerIdx = findDisabledLedger(_ledgerAddress);
        require(ledgerIdx != type(uint256).max, "LIDO: LEDGER_NOT_DISABLED");

        ILedger ledger = ILedger(_ledgerAddress);
        require(ledger.isEmpty(), "LIDO: LEDGER_IS_NOT_EMPTY");

        address lastLedger = disabledLedgers[disabledLedgers.length - 1];
        disabledLedgers[ledgerIdx] = lastLedger;
        disabledLedgers.pop();

        delete ledgerByAddress[_ledgerAddress];
        delete ledgerByStash[ledger.stashAccount()];

        IOracleMaster(ORACLE_MASTER).removeLedger(_ledgerAddress);

        vKSM.approve(address(ledger), 0);

        emit LedgerRemove(_ledgerAddress);
    }

    function findEnabledLedger(address _ledgerAddress) internal returns(uint256) {
        for (uint256 i = 0; i < enabledLedgers.length; ++i) {
            if (enabledLedgers[i] == _ledgerAddress) {
                return i;
            }
        }
        return type(uint256).max;
    }

    function findDisabledLedger(address _ledgerAddress) internal returns(uint256) {
        for (uint256 i = 0; i < disabledLedgers.length; ++i) {
            if (disabledLedgers[i] == _ledgerAddress) {
                return i;
            }
        }
        return type(uint256).max;
    }
    /**
    * @notice Disable ledger, allowed to call only by ROLE_LEDGER_MANAGER
    * @dev That method put ledger to "draining" mode, after ledger drained it can be removed
    * @param _ledgerAddress - target ledger address
    */
    function disableLedger(address _ledgerAddress) external auth(ROLE_LEDGER_MANAGER) {
        require(ledgerByAddress[_ledgerAddress], "LIDO: LEDGER_NOT_FOUND");
        uint256 ledgerIdx = findEnabledLedger(_ledgerAddress);
        require(ledgerIdx != type(uint256).max, "LIDO: LEDGER_NOT_ENABLED");

        address lastLedger = enabledLedgers[enabledLedgers.length - 1];
        enabledLedgers[ledgerIdx] = lastLedger;
        enabledLedgers.pop();

        disabledLedgers.push(_ledgerAddress);

        emit LedgerDisable(_ledgerAddress);
    }
    /**
    * @notice Nominate on behalf of gived stash account, allowed to call only by ROLE_STAKE_MANAGER
    * @dev Method spawns xcm call to relaychain
    * @param _stashAccount - target stash account id
    * @param _validators - validators set to be nominated
    */
    function nominate(bytes32 _stashAccount, bytes32[] calldata _validators) external auth(ROLE_STAKE_MANAGER) {
        require(ledgerByStash[_stashAccount] != address(0),  "LIDO: UNKNOWN_STASH_ACCOUNT");
        require(_validators.length <= RELAY_SPEC.maxValidatorsPerLedger, "LIDO: VALIDATORS_AMOUNT_TOO_BIG");

        ILedger(ledgerByStash[_stashAccount]).nominate(_validators);
    }

    /**
    * @notice Deposit vKSM tokens to the pool and recieve stKSM(liquid staked tokens) instead.
              User should approve tokens before executing this call.
    * @dev Method accoumulate vKSMs on contract
    * @param _amount - amount of vKSM tokens to be deposited
    */
    function deposit(uint256 _amount) external whenNotPaused {
        vKSM.transferFrom(msg.sender, address(this), _amount);

        _submit(_amount);

        emit Deposited(msg.sender, _amount);
    }

    /**
    * @notice Create request to redeem vKSM in exchange of stKSM. stKSM will be instantly burned and
              created claim order, (see `getUnbonded` method).
              User can have up to 10 redeem requests in parallel.
    * @param _amount - amount of stKSM tokens to be redeemed
    */
    function redeem(uint256 _amount) external whenNotPaused {
        uint256 _shares = getSharesByPooledKSM(_amount);
        require(_shares > 0, "LIDO: AMOUNT_TOO_LOW");
        require(_shares <= _sharesOf(msg.sender), "LIDO: REDEEM_AMOUNT_EXCEEDS_BALANCE");
        require(claimOrders[msg.sender].length < MAX_CLAIMS, "LIDO: MAX_CLAIMS_EXCEEDS");

        _burnShares(msg.sender, _shares);
        fundRaisedBalance -= _amount;
        bufferedRedeems += _amount;

        Claim memory newClaim = Claim(_amount, uint64(block.timestamp) + RELAY_SPEC.unbondingPeriod);
        claimOrders[msg.sender].push(newClaim);
        pendingClaimsTotal += _amount;

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
        uint256 readyToClaim = 0;
        uint256 readyToClaimCount = 0;
        Claim[] storage orders = claimOrders[msg.sender];

        for (uint256 i = 0; i < orders.length; ++i) {
            if (orders[i].timeout < block.timestamp) {
                readyToClaim += orders[i].balance;
                readyToClaimCount += 1;
            }
            else {
                orders[i - readyToClaimCount] = orders[i];
            }
        }

        // remove claimed items
        for (uint256 i = 0; i < readyToClaimCount; ++i) { orders.pop(); }

        if (readyToClaim > 0) {
            require(readyToClaim <= vKSM.balanceOf(address(this)), "LIDO: CLAIM_EXCEEDS_BALANCE");
            vKSM.transfer(msg.sender, readyToClaim);
            pendingClaimsTotal -= readyToClaim;
            emit Claimed(msg.sender, readyToClaim);
        }
    }

    /**
    * @notice Distribute rewards earned by ledger, allowed to call only by ledger
    */
    function distributeRewards(uint256 _totalRewards, uint256 ledgerBalance) external {
        require(ledgerByAddress[msg.sender], "LIDO: NOT_FROM_LEDGER");

        Types.Fee memory _fee = FEE;

        // it's `feeDevelopers` + `feeTreasure`
        uint256 _feeDevTreasure = uint256(_fee.developers + _fee.treasury);
        assert(_feeDevTreasure>0);

        fundRaisedBalance += _totalRewards;

        ledgerStake[msg.sender] += _totalRewards;

        uint256 _rewards = _totalRewards * _feeDevTreasure / uint256(10000 - _fee.operators);
        uint256 denom = _getTotalPooledKSM()  - _rewards;
        uint256 shares2mint = _getTotalPooledKSM();
        if (denom > 0) shares2mint = _rewards * _getTotalShares() / denom;

        _mintShares(treasury, shares2mint);

        uint256 _devShares = shares2mint *  uint256(_fee.developers) / _feeDevTreasure;
        _transferShares(treasury, developers, _devShares);
        _emitTransferAfterMintingShares(developers, _devShares);
        _emitTransferAfterMintingShares(treasury, shares2mint - _devShares);

        emit Rewards(msg.sender, _totalRewards, ledgerBalance);
    }

    /**
    * @notice Distribute lossed by ledger, allowed to call only by ledger
    */
    function distributeLosses(uint256 _totalLosses, uint256 ledgerBalance) external {
        require(ledgerByAddress[msg.sender], "LIDO: NOT_FROM_LEDGER");

        fundRaisedBalance -= _totalLosses;
        ledgerStake[msg.sender] -= _totalLosses;

        emit Losses(msg.sender, _totalLosses, ledgerBalance);
    }

    /**
    * @notice Flush stakes, allowed to call only by oracle master
    * @dev This method distributes buffered stakes between ledgers by soft manner
    */
    function flushStakes() external {
        require(msg.sender == ORACLE_MASTER, "LIDO: NOT_FROM_ORACLE_MASTER");

        _softRebalanceStakes();
    }

    /**
    * @notice Force rebalance stake accross ledgers, allowed to call only by ROLE_STAKE_MANAGER
    * @dev In some cases(due to rewards distribution) real ledger stakes can become different
        from target, so that method fixes that lag.
    */
    function forceRebalanceStake() external auth(ROLE_STAKE_MANAGER) {
        _forceRebalanceStakes();

        bufferedDeposits = 0;
        bufferedRedeems = 0;
    }

    /**
    * @notice Refresh allowance for each ledger, allowed to call only by ROLE_LEDGER_MANAGER
    */
    function refreshAllowances() external auth(ROLE_LEDGER_MANAGER) {
        for (uint i = 0; i < enabledLedgers.length; i++) {
            vKSM.approve(enabledLedgers[i], type(uint256).max);
        }
    }

    /**
    * @notice Rebalance stake accross ledgers.
    */
    function _forceRebalanceStakes() internal {
        uint256 totalStake = getTotalPooledKSM();

        uint256 stakesSum = 0;
        address nonZeroLedged = address(0);

        uint _length = enabledLedgers.length;
        uint256 stake = totalStake / _length;
        for (uint i = 0; i < _length; i++) {
            stakesSum += stake;
            ledgerStake[enabledLedgers[i]] = stake;

            if (nonZeroLedged == address(0)) {
                nonZeroLedged = enabledLedgers[i];
            }
        }

        // need to compensate remainder of integer division
        // if we have at least one non zero ledger
        uint256 remainingDust = totalStake - stakesSum;
        if (remainingDust > 0 && nonZeroLedged != address(0)) {
            ledgerStake[nonZeroLedged] += remainingDust;
        }
    }

    /**
    * @notice Rebalance stake accross ledgers by soft manner.
    */
    function _softRebalanceStakes() internal {
        if (bufferedDeposits > 0 || bufferedRedeems > 0) {
            if (disabledLedgers.length > 0) {
                bufferedRedeems = _processDisabledLedgers(bufferedRedeems);
            }
            _processEnabled(bufferedDeposits.toInt256() - bufferedRedeems.toInt256());

            bufferedDeposits = 0;
            bufferedRedeems = 0;
        }
    }

    function _processDisabledLedgers(uint256 redeems) internal returns(uint256 remainingRedeems) {
        uint256 disabledLength = disabledLedgers.length;
        uint256 stakesSum = 0;
        uint256 actualRedeems = 0;

        for (uint256 i = 0; i < disabledLength; ++i) {
            stakesSum += ledgerStake[disabledLedgers[i]];
        }

        for (uint256 i = 0; i < disabledLength; ++i) {
            uint256 currentStake = ledgerStake[disabledLedgers[i]];
            uint256 decrement = redeems * currentStake / stakesSum;
            decrement = decrement > currentStake ? currentStake : decrement;
            ledgerStake[disabledLedgers[i]] = currentStake - decrement;
            actualRedeems += decrement;
        }

        return redeems - actualRedeems;
    }

    function _processEnabled(int256 _stake) internal {
        uint256 ledgersLength = enabledLedgers.length;

        int256[] memory diffs = new int256[](ledgersLength);
        address[] memory ledgersCache = new address[](ledgersLength);
        int256[] memory ledgerStakesCache = new int256[](ledgersLength);

        int256 activeDiffsSum = 0;
        int256 totalChange = 0;
        int256 preciseDiffSum = 0;

        {
            uint256 targetStake = getTotalPooledKSM() / ledgersLength;
            int256 diff = 0;
            for (uint256 i = 0; i < ledgersLength; ++i) {
                ledgersCache[i] = enabledLedgers[i];
                ledgerStakesCache[i] = int256(ledgerStake[ledgersCache[i]]);

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
                for (uint256 i = 0; i < ledgersLength; ++i) {
                    ledgerStake[ledgersCache[i]] += uint256(remaining);
                    break;
                }
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
    }

    /**
    * @notice Process user deposit, mints stKSM and increase the pool buffer
    * @return amount of stKSM shares generated
    */
    function _submit(uint256 _deposit) internal returns (uint256) {
        address sender = msg.sender;

        require(_deposit != 0, "LIDO: ZERO_DEPOSIT");

        uint256 sharesAmount = getSharesByPooledKSM(_deposit);
        if (sharesAmount == 0) {
            // totalPooledKSM is 0: either the first-ever deposit or complete slashing
            // assume that shares correspond to KSM as 1-to-1
            sharesAmount = _deposit;
        }

        fundRaisedBalance += _deposit;
        bufferedDeposits += _deposit;
        _mintShares(sender, sharesAmount);

        _emitTransferAfterMintingShares(sender, sharesAmount);
        return sharesAmount;
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
}
