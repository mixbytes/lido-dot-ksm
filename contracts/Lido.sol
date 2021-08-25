// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import "../interfaces/IOracleMaster.sol";
import "../interfaces/ILedger.sol";
import "../interfaces/IvKSM.sol";
import "../interfaces/IAuthManager.sol";

import "./LKSM.sol";


contract Lido is LKSM {
    using Clones for address;
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    
    // Records a deposit made by a user
    event Submitted(address indexed sender, uint256 amount, address referral);
    // The `_amount` of KSM/(in the future DOT) was sent to the deposit function.
    event Unbuffered(uint256 amount);
    // Fee was updated
    event FeeSet(uint16 feeBasisPoints);

    event LegderAdd(
        address addr,
        bytes32 stashAccount,
        bytes32 controllerAccount,
        uint256 share
    );

    event LegderRemove(
        address addr
    );

    event LegderSetShare(
        address addr,
        uint256 share
    );


    // sum of all losses
    uint128 private lossBalance;

    // sum of all deposits and rewards
    uint128 private fundRaisedBalance;

    struct Claim {
        uint128 balance;
        uint128 timeout;
    }
    // one claim for account
    mapping(address => Claim) private claimOrders;

    // Ledger accounts 
    EnumerableMap.UintToAddressMap private ledgers;

    // Map to check ledger existence by address
    mapping(address => bool) private ledgerByAddress;

    // Ledger shares map
    mapping(address => uint128) public ledgerShares;

    // Sum of all ledger shares
    uint128 public legderSharesTotal;


    // vKSM precompile
    IvKSM internal vKSM = IvKSM(0x0000000000000000000000000000000000000801);
    // AUX relay call builder precompile
    address internal AUX = 0x0000000000000000000000000000000000000801;
    // Virtual accounts precompile
    address internal vAccounts = 0x0000000000000000000000000000000000000801;


    // auth manager contract address
    address public AUTH_MANAGER;

    // Maximum number of ledgers
    uint256 public MAX_LEDGERS_AMOUNT = 200;

    // Who pay off relay chain transaction fees
    bytes32 public GARANTOR = 0x00;

    // fee interest in basis points
    uint16 public FEE_BP = 200;
    
    // ledger clone template contract
    address public LEDGER_CLONE;
    
    // oracle master contract
    address public ORACLE_MASTER;

    // relay spec
    Types.RelaySpec public RELAY_SPEC;


    // default interest value in base points
    uint16 internal constant DEFAULT_FEE = 1000;

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


    modifier auth(bytes32 role) {
        require(IAuthManager(AUTH_MANAGER).has(role, msg.sender), "UNAUTHOROZED");
        _;
    }


    function initialize(
        address _authManager,
        address _vKSM,
        address _AUX,
        address _vAccounts
    ) external {
        if (_vKSM != address(0x0)) { //TODO remove after tests
            vKSM = IvKSM(_vKSM);
            AUX = _AUX;
            vAccounts = _vAccounts;
        }

        AUTH_MANAGER = _authManager;
    }

    fallback() external {
        revert("FORBIDDEN");
    }

    /**
    * @dev API in base points 0 - 100000.
    */
    function getCurrentAPY() external view returns (uint256){
        // todo. now 5.4%
        return 540;
    }

    /**
    * @dev Return caller unbonding balance and balance that is ready for claim
    */
    function getUnbonded(address holder) external view returns (uint256) {
        uint256 _balance = claimOrders[holder].balance;
        if (claimOrders[holder].timeout < block.timestamp) {
            return _balance;
        }
        return 0;
    }

    /**
    * @dev Return relay chain stash account addresses
    */
    function getStashAccounts() public view returns (Types.Stash[] memory) {
        Types.Stash[] memory _stashes = new Types.Stash[](ledgers.length());

        for (uint i = 0; i < ledgers.length(); i++) {
            (uint256 key, address ledger) = ledgers.at(i);
            _stashes[i].stashAccount = bytes32(key);
            // todo adjust eraId to `_oracleMaster`
            _stashes[i].eraId = 0;
        }
        return _stashes;
    }

    function getLedgerAddresses() public view returns (address[] memory) {
        address[] memory _addrs = new address[](ledgers.length());

        for (uint i = 0; i < ledgers.length(); i++) {
            (uint256 key, address ledger) = ledgers.at(i);
            _addrs[i] = ledger;
        }
        return _addrs;
    }

    /**
    * @dev Find ledger contract address associated with the stash account
    */
    function findLedger(bytes32 _stashAccount) external view returns (address) {
        (bool _found, address ledger) = ledgers.tryGet(uint256(_stashAccount));
        return ledger;
    }

    function setRelaySpec(Types.RelaySpec calldata _relaySpec) external auth(ROLE_SPEC_MANAGER) {
        require(ORACLE_MASTER != address(0), "ORACLE_MASTER_UNDEFINED");
        require(_relaySpec.genesisTimestamp > 0, "BAD_GENESIS_TIMESTAMP");
        require(_relaySpec.secondsPerEra > 0, "BAD_SECONDS_PER_ERA");
        require(_relaySpec.unbondingPeriod > 0, "BAD_UNBONDING_PERIOD");
        require(_relaySpec.maxValidatorsPerLedger > 0, "BAD_MAX_VALIDATORS_PER_LEDGER");

        //TODO loop through ledgerByAddress and oracles if some params changed

        RELAY_SPEC = _relaySpec;

        IOracleMaster(ORACLE_MASTER).setRelayParams(_relaySpec.genesisTimestamp, _relaySpec.secondsPerEra);
    }

    /**
    * @dev Update ORACLE_MASTER contract address
    */
    function setOracleMaster(address _oracleMaster) external auth(ROLE_ORACLE_MANAGER) {
        require(ORACLE_MASTER == address(0), "ORACLE_MASTER_ALREADY_DEFINED");
        ORACLE_MASTER = _oracleMaster;
    }

    /**
    * @dev Update ledger master contract address
    */
    function setLedgerClone(address _ledgerClone) external auth(ROLE_LEDGER_MANAGER) {
        require(ledgers.length() == 0, "ONLY_ONCE");
        LEDGER_CLONE = _ledgerClone;
    }

    function setFeeBP(uint16 _feeBP) external auth(ROLE_FEE_MANAGER) {
        FEE_BP = _feeBP;
        emit FeeSet(_feeBP);
    }
    
    /**
    *   @notice Stop pool routine operations
    */
    function pause() external auth(ROLE_PAUSE_MANAGER) {
        _pause();
    }

    /**
    * @notice Resume pool routine operations
    */
    function resume() external auth(ROLE_PAUSE_MANAGER) {
        _unpause();
    }

    function addLedger(
        bytes32 _stashAccount, 
        bytes32 _controllerAccount, 
        uint128 _share
    ) 
        external 
        auth(ROLE_LEDGER_MANAGER) 
        returns(address) 
    {
        require(LEDGER_CLONE != address(0), "UNSPECIFIED_LEDGER_CLONE");
        require(ORACLE_MASTER != address(0), "NO_ORACLE_MASTER");
        require(ledgers.length() < MAX_LEDGERS_AMOUNT, "LEDGERS_POOL_LIMIT");
        require(!ledgers.contains(uint256(_stashAccount)), "STASH_ALREADY_EXISTS");

        address ledger = LEDGER_CLONE.cloneDeterministic(_stashAccount);
        // skip one era before commissioning
        ILedger(ledger).initialize(
            _stashAccount, 
            _controllerAccount, 
            address(vKSM),
            AUX,
            vAccounts,
            RELAY_SPEC.minNominatorBalance
        );
        ledgers.set(uint256(_stashAccount), ledger);
        ledgerByAddress[ledger] = true;
        ledgerShares[ledger] = _share;
        legderSharesTotal += _share;

        IOracleMaster(ORACLE_MASTER).addLedger(ledger);

        _rebalanceStakes();

        emit LegderAdd(ledger, _stashAccount, _controllerAccount, _share);
        return ledger;
    }

    function setLedgerShare(address _ledger, uint128 _newShare) external auth(ROLE_LEDGER_MANAGER) {
        require(ledgerByAddress[_ledger], "LEDGER_BOT_FOUND");

        legderSharesTotal -= ledgerShares[_ledger];
        ledgerShares[_ledger] = _newShare;
        legderSharesTotal += _newShare;

        _rebalanceStakes();

        emit LegderSetShare(_ledger, _newShare);
    }

    function removeLedger(address _ledgerAddress) external auth(ROLE_LEDGER_MANAGER) {
        require(ledgerByAddress[_ledgerAddress], "LEDGER_NOT_FOUND");
        require(ledgerShares[_ledgerAddress] == 0, "LEGDER_HAS_NON_ZERO_SHARE");
        
        ILedger ledger = ILedger(_ledgerAddress);
        require(ledger.status() == Types.LedgerStatus.Idle, "LEDGER_NOT_IDLE");

        ledgers.remove(uint256(ledger.stashAccount()));
        delete ledgerByAddress[_ledgerAddress];
        delete ledgerShares[_ledgerAddress];

        IOracleMaster(ORACLE_MASTER).removeLedger(_ledgerAddress);

        _rebalanceStakes();

        emit LegderRemove(_ledgerAddress);
    }

    /**
    * @dev invoke pallet_stake::nominate on the relay side
    */
    function nominate(bytes32 _stashAccount, bytes32[] calldata validators) external auth(ROLE_STAKE_MANAGER) {
        address ledger = ledgers.get(uint256(_stashAccount), "UNKNOWN_STASH_ACCOUNT");

        ILedger(ledger).nominate(validators);
    }

    /**
    * @dev Deposit LKSM returning LKSM
    */
    function deposit(uint256 amount) external whenNotPaused {
        assert( amount< type(uint128).max );
        vKSM.transferFrom(msg.sender, address(this), amount);

        _submit(address(0), amount);

        uint128 _amount = uint128(amount);

        fundRaisedBalance += _amount;

        _distributeStake(_amount);
    }

    /**
    * @dev Redeem LKSM in exchange for vKSM. LKSM will be locked until unbonded term ends
    */
    function redeem(uint256 amount) external whenNotPaused {
        assert( amount< type(uint128).max );
        uint256 _shares = getSharesByPooledKSM(amount);
        require(_shares <= _sharesOf(msg.sender), "REDEEM_AMOUNT_EXCEEDS_BALANCE");

        _burnShares(msg.sender, _shares);

        Claim memory _claim = claimOrders[msg.sender];
        uint128 _amount = uint128(amount);
        _claim.balance += _amount;
        _claim.timeout = uint128(block.timestamp) + RELAY_SPEC.unbondingPeriod;

        fundRaisedBalance -= uint128(amount);
        claimOrders[msg.sender] = _claim;

        _distributeUnstake(_amount);
    }

    /**
    * @dev Claim unbonded vKSM burning locked LKSM
    */
    function claimUnbonded() external whenNotPaused {
        uint128 amount = claimOrders[msg.sender].balance;
        require(amount > 0, "CLAIM_NOT_FOUND");
        if (claimOrders[msg.sender].timeout < block.timestamp) {
            uint128 _buffered = uint128(vKSM.balanceOf(address(this)));
            require(_buffered >= amount, "CLAIM_BALANCE_ERROR");

            delete claimOrders[msg.sender];

            uint256 sharesAmount = getSharesByPooledKSM(amount);
            vKSM.transfer(msg.sender, amount);
        }
    }

    function distributeRewards(uint128 _totalRewards) external {
        require(ledgerByAddress[msg.sender], "NOT_FROM_LEDGER");

        uint256 feeBasis = uint256(FEE_BP);

        fundRaisedBalance += _totalRewards;

        uint256 shares2mint = (
            uint256(_totalRewards) * feeBasis * _getTotalShares()
                / 
            (_getTotalPooledKSM() * 10000 - (feeBasis * uint256(_totalRewards)))
        );

        _mintShares(address(this), shares2mint);
    }

    function forceRebalanceStake() external auth(ROLE_STAKE_MANAGER) {
        _rebalanceStakes();
    }

    function _distributeStake(uint128 _amount) internal {
        if (_amount == 0) {
            return;
        }

        for (uint i = 0; i < ledgers.length(); i++) {
            (uint256 _key, address ledger) = ledgers.at(i);
            if (ledgerShares[ledger] > 0) {
                uint128 _chunk = _amount * ledgerShares[ledger] / legderSharesTotal;

                vKSM.approve(ledger, vKSM.allowance(address(this), ledger) + uint256(_chunk));
                ILedger(ledger).stake(_chunk);
            }
        }
    }

    function _distributeUnstake(uint128 _amount) internal {
        if (_amount == 0) {
            return;
        }

        for (uint i = 0; i < ledgers.length(); i++) {
            (uint256 _key, address ledger) = ledgers.at(i);
            if (ledgerShares[ledger] > 0) {
                uint128 _chunk = _amount * ledgerShares[ledger] / legderSharesTotal;

                ILedger(ledger).unstake(_chunk);
            }
        }
    }

    function _rebalanceStakes() internal {
        uint128 totalStake = uint128(getTotalPooledKSM());

        for (uint i = 0; i < ledgers.length(); i++) {
            (uint256 _key, address ledger) = ledgers.at(i);
            uint128 stake = uint128(uint256(totalStake) * ledgerShares[ledger] / legderSharesTotal);
            vKSM.approve(ledger, stake);
            ILedger(ledger).exactStake(stake);
        }
    }

    /**
    * @dev Process user deposit, mints LKSM and increase the pool buffer
    * @param _referral address of referral.
    * @return amount of StETH shares generated
    */
    function _submit(address _referral, uint256 _deposit) internal whenNotPaused returns (uint256) {
        address sender = msg.sender;

        require(_deposit != 0, "ZERO_DEPOSIT");

        uint256 sharesAmount = getSharesByPooledKSM(_deposit);
        if (sharesAmount == 0) {
            // totalPooledKSM is 0: either the first-ever deposit or complete slashing
            // assume that shares correspond to KSM as 1-to-1
            sharesAmount = _deposit;
        }

        _mintShares(sender, sharesAmount);
        emit Submitted(sender, _deposit, _referral);

        _emitTransferAfterMintingShares(sender, sharesAmount);
        return sharesAmount;
    }


    /**
    * @dev Emits an {Transfer} event where from is 0 address. Indicates mint events.
    */
    function _emitTransferAfterMintingShares(address _to, uint256 _sharesAmount) internal {
        emit Transfer(address(0), _to, getPooledKSMByShares(_sharesAmount));
    }

    function _getTotalPooledKSM() internal view override returns (uint256) {
        return fundRaisedBalance - lossBalance;
    }
}
