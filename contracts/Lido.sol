// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "../interfaces/ILidoOracle.sol";
import "../interfaces/ILido.sol";
import "../interfaces/IAUX.sol";
import "../interfaces/IvKSM.sol";
import "../interfaces/IvAccounts.sol";
import "../interfaces/ILedger.sol";
import "./LKSM.sol";
import "./Ledger.sol";

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/utils/math/SafeMath.sol";
import "@openzeppelin/proxy/Clones.sol";
import "@openzeppelin/utils/structs/EnumerableMap.sol";

contract Lido is ILido, LKSM {
    using Clones for address;
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    event LegderAdded(
        address addr,
        bytes32 stashAccount,
        bytes32 controllerAccount,
        uint256 era
    );

    // Maximum number of oracle committee members
    uint256 private constant MAX_STASH_ACCOUNTS = 200;

    uint256 private constant MAX_VALIDATOR_PER_STASH = 16;
    // Missing member index
    uint256 internal constant MEMBER_NOT_FOUND = type(uint256).max;

    // 7 + 2 days = 777600 sec for Kusama, 28 + 2 days= 2592000 sec for Polkadot
    uint32 internal unbondingPeriod = 777600;
    // default interest value in base points
    uint16 internal constant DEFAULT_FEE = 1000;

    address  private stake_manager;
    address  private spec_manager;
    // bool    private initialized;
    // todo remove before release
    // uint256 internal constant MIN_PARACHAIN_BALANCE = 1_000_000_000;
    // todo remove before release
    // uint256 private  parachainBalance;
    // ledger master contract
    address private ledgerMaster;
    // oracle contract
    address public  oracle;
    // fee interest in basis points
    uint16  public  feeBP;
    // difference between vKSM.balanceOf(this) and bufferedBalance comes from downward transfer

    uint128 private lossBalance;
    uint128 private fundRaisedBalance;
    // uint128 private claimDebt;

    struct Claim {
        uint128 balance;
        uint128 timeout;
    }
    // one claim for account
    mapping(address => Claim) private claimOrders;
    // vKSM precompile
    IvKSM internal vKSM = IvKSM(0x0000000000000000000000000000000000000801);
    // AUX relay call builder precompile
    IAUX internal AUX = IAUX(0x0000000000000000000000000000000000000801);
    // Virtual accounts precompile
    IvAccounts internal vAccounts = IvAccounts(0x0000000000000000000000000000000000000801);
    // Who pay off relay chain transaction fees
    bytes32 internal constant GARANTOR = 0x00;

    // Ledger accounts (start eraId + Ledger contract address)
    EnumerableMap.UintToAddressMap private members;

    // Map to check ledger existence by address
    mapping(address => bool) private ledgers;

    // Ledger shares map
    mapping(address => uint128) public ledgerShares;

    // Sum of all shares
    uint128 public legderSharesTotal;

    // existential deposit value for relay-chain currency.
    // Polkadot has 100 CENTS = 1 DOT where DOT = 10_000_000_000;
    // Kusama has 1 CENTS. CENTS = KSM / 30_000 where KSM = 1_000_000_000_000
    uint128 internal minStashBalance;

    constructor(address _vKSM, address _AUX, address _vAccounts) {
        if (_vKSM != address(0x0)) { //TODO remove after tests
            vKSM = IvKSM(_vKSM);
            AUX = IAUX(_AUX);
            vAccounts = IvAccounts(_vAccounts);
        }

        initialize();
    }

    function initialize() internal {
        feeBP = DEFAULT_FEE;
        minStashBalance = 33333334;
    }

    modifier auth(address manager) {
        // todo  Manager contract along with LidoOracle . require(msg.sender == manager, "FORBIDDEN");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracle);
        _;
    }

    /**
    *   @notice Stop pool routine operations
    */
    function pause() external auth(spec_manager) {
        _pause();
    }

    /**
    * @notice Resume pool routine operations
    */
    function resume() external auth(spec_manager) {
        _unpause();
    }

    fallback() external {
        revert("FORBIDDEN");
    }

    /**
    * @dev API in base points 0 - 100000.
    */
    function getCurrentAPY() external override view returns (uint256){
        // todo. now 5.4%
        return 540;
    }


    function getMinStashBalance() external view override returns (uint128){
        return minStashBalance;
    }

    function addLedger(bytes32 _stashAccount, bytes32 _controllerAccount, uint128 share) external auth(spec_manager) returns(address) {
        require(ledgerMaster != address(0), 'UNSPECIFIED_LEDGER');
        require(oracle != address(0), 'NO_ORACLE');
        require(members.length() < MAX_STASH_ACCOUNTS, 'STASH_POOL_LIMIT');
        require(!members.contains(uint256(_stashAccount)), 'STASH_ALREADY_EXISTS');

        address ledger = ledgerMaster.cloneDeterministic(_stashAccount);
        // skip one era before commissioning
        Ledger(ledger).initialize(
            _stashAccount, 
            _controllerAccount, 
            ILidoOracle(oracle).getCurrentEraId() + 1,
            address(vKSM),
            address(AUX),
            address(vAccounts)
        );
        members.set(uint256(_stashAccount), ledger);
        ledgers[ledger] = true;
        ledgerShares[ledger] = share;
        legderSharesTotal += share;

        _rebalanceStakes();

        emit LegderAdded(ledger, _stashAccount, _controllerAccount, ILidoOracle(oracle).getCurrentEraId() + 1);
        return ledger;
    }

    function setLedgerShare(address ledger, uint128 newShare) external auth(spec_manager) {
        require(ledgers[ledger], 'LEDGER_BOT_FOUND');

        legderSharesTotal -= ledgerShares[ledger];
        ledgerShares[ledger] = newShare;
        legderSharesTotal += newShare;

        _rebalanceStakes();
    }

    function removeLedger(address ledgerAddress) external auth(spec_manager) {
        require(ledgers[ledgerAddress], 'LEDGER_BOT_FOUND');
        require(ledgerShares[ledgerAddress] == 0, 'LEGDER_HAS_NON_ZERO_SHARE');
        
        Ledger ledger = Ledger(ledgerAddress);
        require(ledger.getStatus() == ILedger.Status.Idle, 'LEDGER_NOT_IDLE');

        members.remove(uint256(ledger.stashAccount()));
        delete ledgers[ledgerAddress];
        delete ledgerShares[ledgerAddress];

        _rebalanceStakes();
    }

    function setQuorum(uint8 _quorum) external override onlyOracle {
        for (uint256 i = 0; i < members.length(); i++) {
            (uint256 key, address ledger) = members.at(i);
            Ledger(ledger).softenQuorum(_quorum);
        }
    }

    function clearReporting() external override onlyOracle {
        for (uint256 i = 0; i < members.length(); i++) {
            (uint256 key, address ledger) = members.at(i);
            Ledger(ledger).clearReporting();
        }
    }

    /**
    * @dev invoke pallet_stake::nominate on the relay side
    */
    function nominate(bytes32 _stashAccount, bytes32[] calldata validators) external auth(stake_manager) {
        address ledger = members.get(uint256(_stashAccount), 'UNKNOWN_STASH_ACCOUNT');

        Ledger(ledger).nominate(validators);
    }

    /**
    * @dev Deposit LKSM returning LKSM
    */
    function deposit(uint256 amount) external override whenNotPaused {
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
    function redeem(uint256 amount) external override whenNotPaused {
        assert( amount< type(uint128).max );
        uint256 _shares = getSharesByPooledKSM(amount);
        require(_shares <= _sharesOf(msg.sender), 'REDEEM_AMOUNT_EXCEEDS_BALANCE');

        _burnShares(msg.sender, _shares);

        Claim memory _claim = claimOrders[msg.sender];
        uint128 _amount = uint128(amount);
        _claim.balance += _amount;
        _claim.timeout = uint128(block.timestamp) + unbondingPeriod;

        fundRaisedBalance -= uint128(amount);
        claimOrders[msg.sender] = _claim;

        _distributeUnstake(_amount);
    }

    /**
    * @dev Return caller unbonding balance and balance that is ready for claim
    */
    function getUnbonded(address holder) external override view returns (uint256){
        uint256 _balance = claimOrders[holder].balance;
        if (claimOrders[holder].timeout < block.timestamp) {
            return (_balance);
        }
        return (0);
    }

    /**
    * @dev Claim unbonded vKSM burning locked LKSM
    */
    function claimUnbonded() external override whenNotPaused {
        uint128 amount = claimOrders[msg.sender].balance;
        require(amount > 0, 'CLAIM_NOT_FOUND');
        if (claimOrders[msg.sender].timeout < block.timestamp) {
            uint128 _buffered = uint128(vKSM.balanceOf(address(this)));
            require(_buffered >= amount, 'CLAIM_BALANCE_ERROR');

            delete claimOrders[msg.sender];

            uint256 sharesAmount = getSharesByPooledKSM(amount);
            vKSM.transfer(msg.sender, amount);
        }
    }

    /**
    * @dev Find ledger contract address associated with the stash account
    */
    function findLedger(bytes32 _stashAccount) external view override returns (address) {
        (bool _found, address ledger) = members.tryGet(uint256(_stashAccount));
        return ledger;
    }

    /**
    * @dev Update oracle contract address
    */
    function setOracle(address _oracle) external auth(spec_manager) {
        oracle = _oracle;
    }

    /**
    * @dev Return oracle contract address
    */
    function getOracle() external view override returns (address) {
        return oracle;
    }

    /**
    * @dev Update ledger master contract address
    */
    function setLedgerMaster(address _ledgerMaster) external auth(spec_manager) {
        require(members.length() == 0, 'ONLY_ONCE');
        ledgerMaster = _ledgerMaster;
    }

    function setFeeBP(uint16 _feeBP) external auth(spec_manager) {
        feeBP = _feeBP;
        emit FeeSet(_feeBP);
    }

    function distributeRewards(uint128 _totalRewards) external override {
        require(ledgers[msg.sender], 'NOT_FROM_LEDGER');

        uint256 feeBasis = uint256(feeBP);

        fundRaisedBalance += _totalRewards;

        uint256 shares2mint = (
            uint256(_totalRewards) * feeBasis * _getTotalShares()
                / 
            (_getTotalPooledKSM() * 10000 - (feeBasis * uint256(_totalRewards)))
        );

        _mintShares(address(this), shares2mint);
    }

    /**
    * @dev Return relay chain stash account addresses
    */
    function getStashAccounts() public override view returns (ILido.Stash[] memory) {
        ILido.Stash[] memory _stashes = new Stash[](members.length());

        for (uint i = 0; i < members.length(); i++) {
            (uint256 key, address ledger) = members.at(i);
            _stashes[i].stashAccount = bytes32(key);
            // todo adjust eraId to `_oracle`
            _stashes[i].eraId = Ledger(ledger).getEraId();
        }
        return _stashes;
    }

    function _distributeStake(uint128 _amount) internal {
        if (_amount == 0) {
            return;
        }

        for (uint i = 0; i < members.length(); i++) {
            (uint256 _key, address ledger) = members.at(i);
            if (ledgerShares[ledger] > 0) {
                uint128 _chunk = _amount * ledgerShares[ledger] / legderSharesTotal;

                vKSM.approve(ledger, vKSM.allowance(address(this), ledger) + uint256(_chunk));
                Ledger(ledger).stake(_chunk);
            }
        }
    }

    function _distributeUnstake(uint128 _amount) internal {
        if (_amount == 0) {
            return;
        }

        for (uint i = 0; i < members.length(); i++) {
            (uint256 _key, address ledger) = members.at(i);
            if (ledgerShares[ledger] > 0) {
                uint128 _chunk = _amount * ledgerShares[ledger] / legderSharesTotal;

                Ledger(ledger).unstake(_chunk);
            }
        }
    }

    function _rebalanceStakes() internal {
        uint128 totalStake = uint128(getTotalPooledKSM());

        for (uint i = 0; i < members.length(); i++) {
            (uint256 _key, address ledger) = members.at(i);
            uint128 stake = uint128(uint256(totalStake) * ledgerShares[ledger] / legderSharesTotal);
            vKSM.approve(ledger, stake);
            Ledger(ledger).exactStake(stake);
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
