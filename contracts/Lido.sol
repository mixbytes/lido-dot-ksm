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
    event Deposited(address indexed sender, uint256 amount);

    // Created redeem order
    event Redeemed(address indexed receiver, uint256 amount);

    // Claimed vKSM tokens back
    event Claimed(address indexed receiver, uint256 amount);

    // Fee was updated
    event FeeSet(uint16 feeBasisPoints);

    // Rewards distributed
    event Rewards(address ledger, uint256 rewards);

    // Added new ledger
    event LedgerAdd(
        address addr,
        bytes32 stashAccount,
        bytes32 controllerAccount,
        uint256 share
    );

    // Ledger removed
    event LedgerRemove(
        address addr
    );

    // Ledger share setted
    event LedgerSetShare(
        address addr,
        uint256 share
    );


    // sum of all losses
    uint256 private lossBalance;

    // sum of all deposits and rewards
    uint256 private fundRaisedBalance;

    struct Claim {
        uint256 balance;
        uint64 timeout;
    }
    // one claim for account
    mapping(address => Claim[]) public claimOrders;

    // Ledger accounts
    EnumerableMap.UintToAddressMap private ledgers;

    // Map to check ledger existence by address
    mapping(address => bool) private ledgerByAddress;

    // Ledger shares map
    mapping(address => uint256) public ledgerShares;

    // Sum of all ledger shares
    uint256 public ledgerSharesTotal;


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
    * @param _AUX - AUX(relaychain calls builder) contract address
    * @param _vAccounts - vAccounts(relaychain calls relayer) contract address
    */
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

    /**
    * @notice Stub fallback for native token, always reverting
    */
    fallback() external {
        revert("FORBIDDEN");
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
        bytes32[] memory _stashes = new bytes32[](ledgers.length());

        for (uint i = 0; i < ledgers.length(); i++) {
            (uint256 key, ) = ledgers.at(i);
            _stashes[i] = bytes32(key);
        }
        return _stashes;
    }

    /**
    * @notice Return ledger contract addresses
    * @dev Each ledger contract linked with single stash account on the relaychain side
    * @return Array of ledger contract addresses
    */
    function getLedgerAddresses() public view returns (address[] memory) {
        address[] memory _addrs = new address[](ledgers.length());

        for (uint i = 0; i < ledgers.length(); i++) {
            (, address ledger) = ledgers.at(i);
            _addrs[i] = ledger;
        }
        return _addrs;
    }

    /**
    * @notice Return ledger address by stash account id
    * @dev If ledger not found function returns ZERO address
    * @param _stashAccount - relaychain stash account id
    * @return Linked ledger contract address
    */
    function findLedger(bytes32 _stashAccount) external view returns (address) {
        (, address ledger) = ledgers.tryGet(uint256(_stashAccount));
        return ledger;
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
        ORACLE_MASTER = _oracleMaster;
    }

    /**
    * @notice Set new ledger clone contract address, allowed to call only by ROLE_LEDGER_MANAGER
    * @dev After setting new ledger clone address, old ledgers won't be affected, be careful
    * @param _ledgerClone - ledger clone address
    */
    function setLedgerClone(address _ledgerClone) external auth(ROLE_LEDGER_MANAGER) {
        LEDGER_CLONE = _ledgerClone;
    }

    /**
    * @notice Set new lido fee, allowed to call only by ROLE_FEE_MANAGER
    * @param _feeBP - fee percent in basis amounts(10000)
    */
    function setFeeBP(uint16 _feeBP) external auth(ROLE_FEE_MANAGER) {
        FEE_BP = _feeBP;
        emit FeeSet(_feeBP);
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
    * @param _share - share of managing stake from total pooled tokens
    * @return created ledger address
    */
    function addLedger(
        bytes32 _stashAccount,
        bytes32 _controllerAccount,
        uint256 _share
    )
        external
        auth(ROLE_LEDGER_MANAGER)
        returns(address)
    {
        require(LEDGER_CLONE != address(0), "LIDO: UNSPECIFIED_LEDGER_CLONE");
        require(ORACLE_MASTER != address(0), "LIDO: NO_ORACLE_MASTER");
        require(ledgers.length() < MAX_LEDGERS_AMOUNT, "LIDO: LEDGERS_POOL_LIMIT");
        require(!ledgers.contains(uint256(_stashAccount)), "LIDO: STASH_ALREADY_EXISTS");

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
        ledgerSharesTotal += _share;

        IOracleMaster(ORACLE_MASTER).addLedger(ledger);

        _rebalanceStakes();

        emit LedgerAdd(ledger, _stashAccount, _controllerAccount, _share);
        return ledger;
    }

    /**
    * @notice Set new share for existing ledger, allowed to call only by ROLE_LEDGER_MANAGER
    * @dev That method triggers rebalancing stakes accross ledgers,
           recommended to carefully calculate share value to avoid significant rebalancing.
    * @param _ledger - target ledger address
    * @param _newShare - new stare amount
    */
    function setLedgerShare(address _ledger, uint256 _newShare) external auth(ROLE_LEDGER_MANAGER) {
        require(ledgerByAddress[_ledger], "LIDO: LEDGER_BOT_FOUND");

        ledgerSharesTotal -= ledgerShares[_ledger];
        ledgerShares[_ledger] = _newShare;
        ledgerSharesTotal += _newShare;

        _rebalanceStakes();

        emit LedgerSetShare(_ledger, _newShare);
    }

    /**
    * @notice Remove ledger, allowed to call only by ROLE_LEDGER_MANAGER
    * @dev That method cannot be executed for running ledger, so need to drain funds
    *      from ledger by setting zero share and wait for unbonding period.
    * @param _ledgerAddress - target ledger address
    */
    function removeLedger(address _ledgerAddress) external auth(ROLE_LEDGER_MANAGER) {
        require(ledgerByAddress[_ledgerAddress], "LIDO: LEDGER_NOT_FOUND");
        require(ledgerShares[_ledgerAddress] == 0, "LIDO: LEGDER_HAS_NON_ZERO_SHARE");

        ILedger ledger = ILedger(_ledgerAddress);
        require(ledger.status() == Types.LedgerStatus.Idle, "LIDO: LEDGER_NOT_IDLE");

        ledgers.remove(uint256(ledger.stashAccount()));
        delete ledgerByAddress[_ledgerAddress];
        delete ledgerShares[_ledgerAddress];

        IOracleMaster(ORACLE_MASTER).removeLedger(_ledgerAddress);

        _rebalanceStakes();

        emit LedgerRemove(_ledgerAddress);
    }

    /**
    * @notice Nominate on behalf of gived stash account, allowed to call only by ROLE_STAKE_MANAGER
    * @dev Method spawns xcm call to relaychain
    * @param _stashAccount - target stash account id
    * @param _validators - validators set to be nominated
    */
    function nominate(bytes32 _stashAccount, bytes32[] calldata _validators) external auth(ROLE_STAKE_MANAGER) {
        address ledger = ledgers.get(uint256(_stashAccount), "UNKNOWN_STASH_ACCOUNT");

        ILedger(ledger).nominate(_validators);
    }

    /**
    * @notice Deposit vKSM tokens to the pool and recieve LKSM(liquid staked tokens) instead.
              User should approve tokens before executing this call.
    * @dev Method accoumulate vKSMs on contract and calculate new stake amounts for each ledger.
    *      No one xcm calls spawns here.
    * @param _amount - amount of vKSM tokens to be deposited
    */
    function deposit(uint256 _amount) external whenNotPaused {
        vKSM.transferFrom(msg.sender, address(this), _amount);

        _submit(_amount);

        _distributeStake(_amount);

        emit Deposited(msg.sender, _amount);
    }

    /**
    * @notice Create request to redeem vKSM in exchange of LKSM. LKSM will be instantly burned and
              created claim order, (see `getUnbonded` method).
              User can have up to 10 redeem requests in parallel.
    * @param _amount - amount of LKSM tokens to be redeemed
    */
    function redeem(uint256 _amount) external whenNotPaused {
        uint256 _shares = getSharesByPooledKSM(_amount);
        require(_shares <= _sharesOf(msg.sender), "LIDO: REDEEM_AMOUNT_EXCEEDS_BALANCE");
        require(claimOrders[msg.sender].length < MAX_CLAIMS, "LIDO: MAX_CLAIMS_EXCEEDS");

        _burnShares(msg.sender, _shares);
        fundRaisedBalance -= _amount;

        Claim memory newClaim = Claim(_amount, uint64(block.timestamp) + RELAY_SPEC.unbondingPeriod);
        claimOrders[msg.sender].push(newClaim);

        _distributeUnstake(_amount);

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
            vKSM.transfer(msg.sender, readyToClaim);
            emit Claimed(msg.sender, readyToClaim);
        }
    }

    /**
    * @notice Distribute rewards earned by ledger, allowed to call only by ledger
    */
    function distributeRewards(uint256 _totalRewards) external {
        require(ledgerByAddress[msg.sender], "LIDO: NOT_FROM_LEDGER");

        uint256 feeBasis = uint256(FEE_BP);

        fundRaisedBalance += _totalRewards;

        uint256 shares2mint = (
            _totalRewards * feeBasis * _getTotalShares()
                /
            (_getTotalPooledKSM() * 10000 - (feeBasis * _totalRewards))
        );

        _mintShares(address(this), shares2mint);
        //TODO mixbytes shares

        emit Rewards(msg.sender, _totalRewards);
    }

    /**
    * @notice Force rebalance stake accross ledgers, allowed to call only by ROLE_STAKE_MANAGER
    * @dev In some cases(due to rewards distribution) real ledger stakes can become different
           from stakes calculated around ledger shares, so that method fixes that lag.
    */
    function forceRebalanceStake() external auth(ROLE_STAKE_MANAGER) {
        _rebalanceStakes();
    }

    /**
    * @notice Distribute new coming stake accross ledgers according their shares.
    */
    function _distributeStake(uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }

        for (uint i = 0; i < ledgers.length(); i++) {
            (, address ledger) = ledgers.at(i);
            if (ledgerShares[ledger] > 0) {
                uint256 _chunk = _amount * ledgerShares[ledger] / ledgerSharesTotal;

                vKSM.approve(ledger, vKSM.allowance(address(this), ledger) + _chunk);
                ILedger(ledger).increaseStake(_chunk);
            }
        }
    }

    /**
    * @notice Distribute unstake accross ledgers according their shares.
    */
    function _distributeUnstake(uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }

        for (uint i = 0; i < ledgers.length(); i++) {
            (, address ledger) = ledgers.at(i);
            if (ledgerShares[ledger] > 0) {
                uint256 _chunk = _amount * ledgerShares[ledger] / ledgerSharesTotal;

                ILedger(ledger).decreaseStake(_chunk);
            }
        }
    }

    /**
    * @notice Rebalance stake accross ledgers according their shares.
    */
    function _rebalanceStakes() internal {
        uint256 totalStake = getTotalPooledKSM();

        for (uint i = 0; i < ledgers.length(); i++) {
            (, address ledger) = ledgers.at(i);
            uint256 stake = totalStake * ledgerShares[ledger] / ledgerSharesTotal;
            vKSM.approve(ledger, stake);
            ILedger(ledger).exactStake(stake);
        }
    }

    /**
    * @notice Process user deposit, mints LKSM and increase the pool buffer
    * @return amount of LKSM shares generated
    */
    function _submit(uint256 _deposit) internal whenNotPaused returns (uint256) {
        address sender = msg.sender;

        require(_deposit != 0, "LIDO: ZERO_DEPOSIT");

        uint256 sharesAmount = getSharesByPooledKSM(_deposit);
        if (sharesAmount == 0) {
            // totalPooledKSM is 0: either the first-ever deposit or complete slashing
            // assume that shares correspond to KSM as 1-to-1
            sharesAmount = _deposit;
        }

        fundRaisedBalance += _deposit;
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
        return fundRaisedBalance - lossBalance;
    }
}
