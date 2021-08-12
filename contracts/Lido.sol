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
    using Clones for address;
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    // Maximum number of oracle committee members
    uint256 private constant MAX_STASH_ACCOUNTS = 200;

    uint256 private constant MAX_VALIDATOR_PER_STASH = 16;
    // Missing member index
    uint256 internal constant MEMBER_NOT_FOUND = type(uint256).max;

    // 7 + 2 days = 777600 sec for Kusama, 28 + 2 days= 2592000 sec for Polkadot
    uint32  internal unbondingPeriod = 777600;
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
    address private  oracle;
    // fee interest in basis points
    uint16  public  feeBP;
    // difference between vKSM.balanceOf(this) and bufferedBalance comes from downward transfer
    // uint128 private bufferedBalance;
    uint128 private accruedRewardBalance;
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
    IvKSM internal constant vKSM = IvKSM(0x0000000000000000000000000000000000000801);
    // AUX relay call builder precompile
    IAUX internal constant AUX = IAUX(0x0000000000000000000000000000000000000801);
    // Virtual accounts precompile
    IvAccounts internal constant vAccounts = IvAccounts(0x0000000000000000000000000000000000000801);
    // Who pay off relay chain transaction fees
    bytes32 internal constant GARANTOR = 0x00;

    // Ledger accounts (start eraId + Ledger contract address)
    EnumerableMap.UintToAddressMap private members;
    // existential deposit value for relay-chain currency.
    // Polkadot has 100 CENTS = 1 DOT where DOT = 10_000_000_000;
    // Kusama has 1 CENTS. CENTS = KSM / 30_000 where KSM = 1_000_000_000_000
    uint128 internal minStashBalance;

    constructor() {
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

    modifier isLedger(bytes32 _stashAccount) {
        (bool _found, address ledger) = _findStash(_stashAccount);
        // todo uncomment
        require(_found && ledger == msg.sender, 'NOT_LEDGER');
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

    function getMinStashBalance() external view override returns (uint128){
        return minStashBalance;
    }

    function addStash(bytes32 _stashAccount, bytes32 _controllerAccount) external auth(spec_manager) {
        require(ledgerMaster != address(0), 'UNSPECIFIED_LEDGER');
        require(oracle != address(0), 'NO_ORACLE');
        require(members.length() < MAX_STASH_ACCOUNTS, 'STASH_POOL_LIMIT');
        // don't care about that, because clone method reverts if stash ledger already exists
        // require(_findStash(_stashAccount) == MEMBER_NOT_FOUND, 'STASH_ALREADY_EXISTS');

        address ledger = ledgerMaster.cloneDeterministic(_stashAccount);
        // skip one era before commissioning
        Ledger(ledger).initialize(_stashAccount, _controllerAccount, ILidoOracle(oracle).getCurrentEraId() + 1);
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
        vAccounts.relayTransactCall(_stashAccount, GARANTOR, DEFAULT_FEE, call);
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

        _increaseDefer(_amount);
    }

    /**
    * @dev Redeem LKSM in exchange for vKSM. LKSM will be locked until unbonded term ends
    */
    function redeem(uint256 amount) external override whenNotPaused {
        assert( amount< type(uint128).max );
        uint256 _shares = getSharesByPooledKSM(amount);
        require(_shares <= _sharesOf(msg.sender), 'REDEEM_AMOUNT_EXCEEDS_BALANCE');

        _transferShares(msg.sender, address(this), _shares);

        Claim memory _claim = claimOrders[msg.sender];
        uint128 _amount = uint128(amount);
        _claim.balance += _amount;
       // claimDebt += _amount;
        _claim.timeout = uint128(block.timestamp) + unbondingPeriod;

        claimOrders[msg.sender] = _claim;
        _decreaseDefer(_amount);
    }
    /**
    * @dev Return caller unbonding balance and balance that is ready for claim
    */
    function getUnbonded(address holder) external override view returns (uint256, uint256){
        uint256 _balance = claimOrders[holder].balance;
        if (claimOrders[holder].timeout < block.timestamp) {
            return (_balance, _balance);
        }
        return (_balance, 0);
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

            _burnShares(address(this), sharesAmount);
            // claimDebt -= amount;

            accruedRewardBalance -= amount;
            fundRaisedBalance -= amount;
        }
    }

    /**
    * @dev Find ledger contract address associated with the stash account
    */
    function findLedger(bytes32 _stashAccount) external view override returns (address) {
        (bool _found, address ledger) = members.tryGet(uint256(_stashAccount));
        //require(_found, 'UNKNOWN_STASH_ACCOUNT');
        return ledger;
    }

    /**
    * @dev Find stash account and return its index in the register
    */
    function _findStash(bytes32 _stashAccount) internal view returns (bool, address){
        // todo compare performance with Clones::predictDeterministicAddress + isContract.
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
    function getStakeAccounts(address _oracle) public override view returns (ILido.Stash[] memory){
        ILido.Stash[] memory _stake = new Stash[](members.length());

        for (uint i = 0; i < members.length(); i++) {
            (uint256 key, address ledger) = members.at(i);
            _stake[i].stashAccount = bytes32(key);
            // todo adjust eraId to `_oracle`
            _stake[i].eraId = Ledger(ledger).getEraId();
        }
        return _stake;
    }

    function _increaseDefer(uint128 _amount) internal {
        if (_amount == 0) {
            return;
        }
        uint128 _length = uint128(members.length());
        uint128 _chunk = (_amount) / _length;


        for (uint i = 0; i < _length; i++) {
            (uint256 _key, address ledger) = members.at(i);
            // todo skip ledgers that have Blocked status
            // todo safe increaseAllowance
            //vKSM.increaseAllowance(ledger, uint256(_chunk));
            vKSM.approve(ledger, vKSM.allowance(address(this), ledger) + uint256(_chunk));

            Ledger(ledger).increaseDefer(_chunk);
        }
    }

    function _decreaseDefer(uint128 _amount) internal {
        if (_amount == 0) {
            return;
        }

        uint128 _length = uint128(members.length());
        uint128 _chunk = (_amount + _length - 1) / _length;

        for (uint i = 0; i < _length; i++) {
            (uint256 _key, address ledger) = members.at(i);
            // todo drain ledgers that have Blocked status
            // todo safe decreaseAllowance
            // vKSM.decreaseAllowance(ledger, uint256(_chunk));
            Ledger(ledger).decreaseDefer(_chunk);
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

    function _getTotalPooledKSM() internal view override returns (uint256) {
        return fundRaisedBalance + accruedRewardBalance - lossBalance;
    }

    function distributeRewards(uint128 _totalRewards, bytes32 _stashAccount) external override isLedger(_stashAccount) {
        uint256 feeBasis = uint256(feeBP);

        accruedRewardBalance += _totalRewards;

        uint256 shares2mint = (
        uint256(_totalRewards) * feeBasis * _getTotalShares()
        / (_getTotalPooledKSM() * 10000 - (feeBasis * uint256(_totalRewards)))
        );

        _mintShares(address(this), shares2mint);
    }
}
