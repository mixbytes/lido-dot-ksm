// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "../interfaces/ILidoOracle.sol";
import "../interfaces/ILido.sol";
import "../interfaces/IAUX.sol";
import "../interfaces/IvKSM.sol";
import "../interfaces/IvAccounts.sol";
import "./LKSM.sol";
import "./Ledger.sol";

import "zeppelin/token/ERC20/IERC20.sol";
import "zeppelin/utils/math/SafeMath.sol";
import "zeppelin/proxy/Clones.sol";
import "zeppelin/utils/structs/EnumerableMap.sol";

contract Lido is ILido, LKSM {
    using SafeMath for uint256;
    using Clones for address;
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    // Maximum number of oracle committee members
    uint256 private constant MAX_STASH_ACCOUNTS = 200;

    uint256 private constant MAX_VALIDATOR_PER_STASH = 16;
    // Missing member index
    uint256 internal constant MEMBER_NOT_FOUND = type(uint256).max;

    // existential deposit value for relay-chain currency.
    // Polkadot has 100 CENTS = 1 DOT where DOT = 10_000_000_000;
    // Kusama has 1 CENTS. CENTS = KSM / 30_000 where KSM = 1_000_000_000_000
    // todo move initializations into initialize() functions
    uint128 internal minStashBalance = 33333334;
    uint8   internal constant MAX_UNLOCKING_CHUNKS = 32;
    // 7 + 2 days = 777600 sec for Kusama, 28 + 2 days= 2592000 sec for Polkadot
    uint32  internal unbondingPeriod = 777600;

    uint16 internal constant DEFAULT_FEE = 10000;

    address  private stake_manager;
    address  private spec_manager;
    bool    private initialized;

    // todo remove before release
    uint256 internal constant MIN_PARACHAIN_BALANCE = 1_000_000_000;
    //todo remove before release
    uint256 private  parachainBalance;

    // ledger master contract
    address private ledgerMaster;

    // oracle contract
    address private  oracle;

    // fee interest in basis points
    uint16  public  feeBP;

    // difference between vKSM.balanceOf(this) and _bufferedBalance comes from downward transfer
    uint256 private _bufferedBalance;
    //uint256 private _transientUpward;
    //uint256 private _transientDownward;
    uint256 private _claimDebt;
    // last total stash account balances
    uint256 private _cachedStakeBalance;

    struct Claim {
        uint256 balance;
        uint128 timeout;
    }
    // one claim for account
    mapping(address => Claim) private claimOrders;

    // vKSM precompile
    IvKSM internal constant vKSM = IvKSM(0x0000000000000000000000000000000000000801);
    // AUX call builder precompile
    IAUX internal constant AUX = IAUX(0x0000000000000000000000000000000000000801);
    // Virtual accounts precompile
    IvAccounts internal constant vAccounts = IvAccounts(0x0000000000000000000000000000000000000801);

    // Who pay off relay chain transaction fees
    bytes32 internal constant GARANTOR = 0x00;

    // Ledger accounts (start eraId + Ledger contract address)
    EnumerableMap.UintToAddressMap private members;

    constructor() {
        initialize();
    }

    function initialize() internal {
        feeBP = DEFAULT_FEE;

        _bufferedBalance = 0;
        //_transientUpward = 0;
        //_transientDownward = 0;
        _claimDebt = 0;
        _cachedStakeBalance = 0;

        parachainBalance = 0;
        oracle = address(0);

        initialized = true;
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

    fallback() external payable {
        revert("FORBIDDEN");
    }

    function addStash(bytes32 _stashAccount, bytes32 _controllerAccount) external auth(spec_manager) {
        require(ledgerMaster != address(0), 'UNSPECIFIED_LEDGER');
        require(members.length() < MAX_STASH_ACCOUNTS, 'STASH_POOL_LIMIT');
        // we don't have to worry about that, because
        // require(_findStash(_stashAccount) == MEMBER_NOT_FOUND, 'STASH_ALREADY_EXISTS');
        // added stash will be used after the next era

        address ledger = ledgerMaster.cloneDeterministic(_stashAccount);
        // skip one era before commissioning
        Ledger(ledger).initialize(_stashAccount, _controllerAccount, ILidoOracle(oracle).getCurrentEraId() + 2);
        members.set(uint256(_stashAccount), ledger);
    }

    function enableStash(bytes32 _stashAccount) external auth(spec_manager) {
        (bool _found, address ledger) = _findStash(_stashAccount);
        require(_found, 'UNKNOWN_STASH_ACCOUNT');

        require(Ledger(ledger).getStatus() == ILidoOracle.StakeStatus.Blocked, 'STASH_ALREADY_STARTED');
        Ledger(ledger).setStatus(ILidoOracle.StakeStatus.Idle);
    }

    function disableStash(bytes32 _stashAccount) external auth(spec_manager) {
        (bool _found, address ledger) = _findStash(_stashAccount);
        require(_found, 'UNKNOWN_STASH_ACCOUNT');

        Ledger(ledger).setStatus(ILidoOracle.StakeStatus.Blocked);
        // todo immediate send Chill + Unbond
    }

    function setQuorum(uint256 _quorum) external override onlyOracle {
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

    //    function reportRelay(address stash,
    //        uint256 index,
    //        uint256 _quorum,
    //        uint64 _eraId,
    //        ILidoOracle.LedgerData calldata staking
    //    ) external override onlyOracle {
    //        Ledger(stash).reportRelay(index, _eraId, _quorum, staking);
    //    }

    /**
    * @dev invoke pallet_stake::nominate on the relay side
    */
    function nominate(bytes32 _stashAccount, bytes32[] calldata validators) external auth(stake_manager) {
        (bool _found, address ledger) = _findStash(_stashAccount);
        require(_found, 'UNKNOWN_STASH_ACCOUNT');

        ILidoOracle.StakeStatus _status = Ledger(ledger).getStatus();
        require(_status == ILidoOracle.StakeStatus.Nominator || _status == ILidoOracle.StakeStatus.Idle || _status == ILidoOracle.StakeStatus.None, 'STASH_WRONG_STATUS');

        bytes[] memory call = new bytes[](1);

        if (_status == ILidoOracle.StakeStatus.None) {
            uint128 freeBalance = Ledger(ledger).getFreeStashBalance();
            require(freeBalance >= minStashBalance, 'STASH_INSUFFICIENT_BALANCE');
            call[0] = AUX.buildBond(Ledger(ledger).controllerAccount(), validators, freeBalance);
        } else {
            require(Ledger(ledger).getLockedStashBalance() >= minStashBalance, 'STASH_INSUFFICIENT_BALANCE');
            call[0] = AUX.buildNominate(validators);
        }
        // todo pore over that
        //members[_index].pendingNominate = true;

        vAccounts.relayTransactCall(_stashAccount, GARANTOR, DEFAULT_FEE, call);
    }

    /**
    * @dev Deposit LKSM returning LKSM
    */
    function deposit(uint256 amount) external override whenNotPaused {
        vKSM.transferFrom(msg.sender, address(this), amount);
        _bufferedBalance = _bufferedBalance.add(amount);
        _submit(address(0), amount);
    }

    /**
    * @dev Redeem LKSM in exchange for vKSM. LKSM will be locked until unbonded term ends
    */
    function redeem(uint256 amount) external override whenNotPaused {
        uint256 _shares = _sharesOf(msg.sender);
        uint256 pooledKSM = getPooledKSMByShares(_shares);
        require(amount <= pooledKSM, 'REDEEM_AMOUNT_EXCEEDS_BALANCE');

        _transferShares(msg.sender, address(this), _shares);

        Claim memory _claim = claimOrders[msg.sender];
        _claim.balance.add(amount);
        _claimDebt = _claimDebt.add(amount);
        _claim.timeout = uint128(block.timestamp) + unbondingPeriod;

        claimOrders[msg.sender] = _claim;
    }
    /**
    * @dev Return caller unbonding balance and balance that is ready for claim
    */
    function getUnbonded() external override view returns (uint256, uint256){
        uint256 _balance = claimOrders[msg.sender].balance;
        if (claimOrders[msg.sender].timeout < block.timestamp) {
            return (_balance, _balance);
        }
        return (_balance, 0);
    }

    /**
    * @dev Claim unbonded vKSM burning locked LKSM
    */
    function claimUnbonded() external override whenNotPaused {
        uint256 _balance = claimOrders[msg.sender].balance;
        require(_balance > 0, 'CLAIM_NOT_FOUND');
        if (claimOrders[msg.sender].timeout < block.timestamp) {
            uint256 _buffered = vKSM.balanceOf(address(this));
            require(_buffered >= _balance, 'CLAIM_BALANCE_ERROR');

            delete claimOrders[msg.sender];

            uint256 sharesAmount = getSharesByPooledKSM(_balance);
            vKSM.transfer(msg.sender, _balance);

            _burnShares(address(this), sharesAmount);
            _claimDebt = _claimDebt.sub(_balance);
        }
    }

    /**
    * @dev Find ledger contract address associated with the stash account
    */
    function findLedger(bytes32 _stashAccount) external view override returns (address) {
        (bool _found, address ledger) = members.tryGet(uint256(_stashAccount));
        require(_found, 'UNKNOWN_STASH_ACCOUNT');
        return ledger;
    }

    /**
    * @dev Find stash account and return its index in the register
    */
    function _findStash(bytes32 _stashAccount) internal view returns (bool, address){
        // todo compare with Clones::predictDeterministicAddress + isContract.
        return members.tryGet(uint256(_stashAccount));
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

    /**
    * @dev Return relay chain stash account addresses
    */
    function getStakeAccounts(uint64 _eraId) public override view returns (bytes32[] memory){
        bytes32[] memory _stake = new bytes32[](members.length());
        uint j = 0;
        for (uint i = 0; i < members.length(); i++) {
            (uint256 key, address ledger) = members.at(i);
            if (Ledger(ledger).startEra() <= _eraId) {
                _stake[j] = bytes32(key);
                j += 1;
            }
        }

        assembly {mstore(_stake, j)}
        return _stake;
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
            // totalControlledEther is 0: either the first-ever deposit or complete slashing
            // assume that shares correspond to Ether 1-to-1
            sharesAmount = _deposit;
        }

        _mintShares(sender, sharesAmount);
        emit Submitted(sender, _deposit, _referral);

        _emitTransferAfterMintingShares(sender, sharesAmount);
        return sharesAmount;
    }

    function setFeeBP(uint16 _feeBP) external auth(spec_manager) {
        feeBP = _feeBP;
        emit FeeSet(_feeBP);
    }

    /**
    * @dev Emits an {Transfer} event where from is 0 address. Indicates mint events.
    */
    function _emitTransferAfterMintingShares(address _to, uint256 _sharesAmount) internal {
        emit Transfer(address(0), _to, getPooledKSMByShares(_sharesAmount));
    }

    /**
    * @dev API in base points 0 - 100000.
    */
    function getCurrentAPY() external override view returns (uint256){
        // todo. now 5.4%
        return 540;
    }

    function _getStashBalance() internal view returns (uint256){
        uint256 total = 0;
        for (uint i = 0; i < members.length(); i++) {
            (uint256 key, address ledger) = members.at(i);
            total += Ledger(ledger).getTotalBalance();
        }
        return total;
    }

    function _getTotalPooledKSM() internal view override returns (uint256) {
        // todo cache _getStashBalance value
        return _bufferedBalance.add(_getStashBalance());
    }

    function distributeRewards(uint256 _totalRewards) internal {
        uint256 feeBasis = uint256(feeBP);
        uint256 shares2mint = (
        _totalRewards.mul(feeBasis).mul(_getTotalShares())
        .div(
            _getTotalPooledKSM().mul(10000)
            .sub(feeBasis.mul(_totalRewards))
        )
        );

        _mintShares(address(this), shares2mint);
    }
}
