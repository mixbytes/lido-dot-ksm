// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

pragma abicoder v2;

import "../interfaces/ILidoOracle.sol";
import "../interfaces/ILido.sol";
import "../interfaces/IAUX.sol";
import "../interfaces/IvKSM.sol";
import "../interfaces/IvAccounts.sol";
import "./LKSM.sol";

import "../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../node_modules/@openzeppelin/contracts/utils/math/SafeMath.sol";


contract Lido is ILido, LKSM {
    using SafeMath for uint256;


    // Maximum number of oracle committee members
    uint256 private constant MAX_STASH_ACCOUNTS = 200;

    uint256 private constant MAX_VALIDATOR_PER_STASH = 20;
    // Missing member index
    uint256 internal constant MEMBER_NOT_FOUND = type(uint256).max;


    // existential deposit value for relay-chain currency.
    // Polkadot has 100 CENTS = 1 DOT. DOT = 10_000_000_000;
    // Kusama has 1 CENTS. CENTS = KSM / 30_000 . KSM = 1_000_000_000_000
    uint128 internal constant MIN_STASH_BALANCE = 33333334;
    uint8   internal constant MAX_UNLOCKING_CHUNKS = 32;
    // 7 + 2 days = 777600 sec for Kusama, 28 + 2 days= 2592000 sec for Polkadot
    uint32  internal constant UNBONDING_PERIOD = 777600;

    uint256 internal constant DEFAULT_FEE = 0;

    address  private stake_manager;
    address  private spec_manager;
    bool    private initialized;

    uint256 internal constant MIN_PARACHAIN_BALANCE = 1_000_000_000;
    //todo remove before release
    uint256 private  parachainBalance;

    // oracle contract
    address private  oracle;

    // fee interest in basis points
    uint16  public  feeBP;

    // difference between vKSM.balanceOf(this) and _bufferedBalance comes from downward transfer
    uint256 private _bufferedBalance;
    uint256 private _transientUpward;
    uint256 private _transientDownward;
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

    struct Stash {
        bytes32 stashAccount;
        bytes32 controllerAccount;
        uint128 activeBalance;
        uint128 freeStashBalance;
        uint128 lockedStashBalance;
        uint128 withdrawbleBalance;
        uint8 unlockingChunks;
        uint64 startEra;
        bool pendingNominate;

        uint256 transientDownwardBalance;
        uint256 transientUpwardBalance;

        ILidoOracle.StakeStatus stakeStatus;
    }

    // stash accounts
    Stash[] private members;
    // current era
    uint64  eraId;

    constructor() {
        initialize();
    }

    function initialize() internal {
        eraId = 0;
        feeBP = 100;

        _bufferedBalance = 0;
        _transientUpward = 0;
        _transientDownward = 0;
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
        require(members.length < MAX_STASH_ACCOUNTS, 'STASH_POOL_LIMIT');
        require(_findStash(_stashAccount) == MEMBER_NOT_FOUND, 'STASH_ALREADY_EXISTS');
        // added stash will be used after the next era
        members.push(Stash(_stashAccount, _controllerAccount, 0, 0, 0, 0, 0, eraId + 2, false, 0, 0, ILidoOracle.StakeStatus.Idle));
    }

    function enableStash(bytes32 _stashAccount) external auth(spec_manager) {
        uint256 _index = _findStash(_stashAccount);
        require(_index != MEMBER_NOT_FOUND, 'STASH_ACCOUNT');
        require(members[_index].stakeStatus == ILidoOracle.StakeStatus.Blocked, 'STASH_ALREADY_STARTED');

        members[_index].stakeStatus = ILidoOracle.StakeStatus.Idle;
    }

    function disableStash(bytes32 _stashAccount) external auth(spec_manager) {
        uint256 _index = _findStash(_stashAccount);
        require(_index != MEMBER_NOT_FOUND, 'STASH_ACCOUNT');

        members[_index].stakeStatus = ILidoOracle.StakeStatus.Blocked;
        // todo immediate send Chill + Unbond
    }

    function nominate(bytes32 _stashAccount, bytes32[] calldata validators) external auth(stake_manager) {
        uint256 _index = _findStash(_stashAccount);
        require(_index != MEMBER_NOT_FOUND, 'STASH_ACCOUNT');

        ILidoOracle.StakeStatus _status = members[_index].stakeStatus;
        require(_status == ILidoOracle.StakeStatus.Nominator || _status == ILidoOracle.StakeStatus.Idle || _status == ILidoOracle.StakeStatus.None, 'STASH_WRONG_STATUS');

        // todo immediate send (Bond) + Nominate

        bytes[] memory call = new bytes[](1);

        if (_status == ILidoOracle.StakeStatus.None) {
            require(members[_index].freeStashBalance >= MIN_STASH_BALANCE, 'STASH_INSUFFICIENT_BALANCE');
            call[0] = AUX.buildBond(members[_index].controllerAccount, validators, members[_index].freeStashBalance);
        } else {
            require(members[_index].lockedStashBalance >= MIN_STASH_BALANCE, 'STASH_INSUFFICIENT_BALANCE');
            call[0] = AUX.buildNominate(validators);
        }

        members[_index].pendingNominate = true;

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

        _claim.timeout = uint128(block.timestamp) + UNBONDING_PERIOD;
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

            //            if(_balance < _buffered) {
            //                _balance = _buffered;
            //                claimOrders[msg.sender].balance -= _buffered;
            //            }else{
            //                delete claimOrders[msg.sender];
            //            }

        }
    }

    /**
    * @dev Find stash account and return its index in the register
    */
    function _findStash(bytes32 _stash) internal view returns (uint256){
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i].stashAccount == _stash) {
                return i;
            }
        }
        return MEMBER_NOT_FOUND;
    }
    /**
    * @dev Update oracle contract address
    */
    function setOracle(address _oracle) external auth(spec_manager) {
        oracle = _oracle;
    }

    function getWithdrawableBalance(ILidoOracle.Ledger memory ledger, uint64 _eraId) internal view returns (uint128){
        uint256 _balance = 0;
        for (uint i = 0; i < ledger.unlocking.length; i++) {
            if (ledger.unlocking[i].era >= _eraId) {
                _balance = _balance.add(ledger.unlocking[i].balance);
            }
        }
        return uint128(_balance);
    }

    /**
    * @dev Oracle entry point. Called by oracle contract once per era.
    */
    function reportRelay(uint64 _eraId, ILidoOracle.StakeReport memory staking) external override {
        // todo uncomment the next line before release
        //require(msg.sender == oracle, 'ORACLE_FORBIDDEN');
        require(members.length >= staking.stakeLedger.length, 'REPORT_LENGTH_MISMATCH');

        eraId = _eraId;
        // todo remove before release
        parachainBalance = staking.parachainBalance;

        uint256 _vKSMBalance = vKSM.balanceOf(address(this));

        bool positiveBalance = (_claimDebt <= _vKSMBalance);
        uint256 imbalance = 0;

        if (positiveBalance) {
            // for stake
            imbalance = _vKSMBalance - _claimDebt;
        } else {
            // for unstake
            imbalance = _claimDebt - _vKSMBalance;
        }

        // todo handle transfer
        uint256 _rewardsBalance = 0;
        // update
        for (uint i = 0; i < members.length; i++) {
            require(members[i].stashAccount == staking.stakeLedger[i].stashAccount, 'REPORT_STASH_MISMATCH');
            require(members[i].controllerAccount == staking.stakeLedger[i].controllerAccount, 'REPORT_CONTROLLER_MISMATCH');

            // assume that all transfers are completed
            _rewardsBalance += (members[i].freeStashBalance + members[i].lockedStashBalance
            - staking.stakeLedger[i].stashBalance) - members[i].transientUpwardBalance + members[i].transientUpwardBalance;
            // todo make it more sophisticated
            members[i].transientUpwardBalance = 0;
            members[i].transientDownwardBalance = 0;

            members[i].stakeStatus = staking.stakeLedger[i].stakeStatus;

            members[i].freeStashBalance = staking.stakeLedger[i].stashBalance - staking.stakeLedger[i].totalBalance;
            members[i].lockedStashBalance = staking.stakeLedger[i].totalBalance;
            members[i].unlockingChunks = uint8(staking.stakeLedger[i].unlocking.length);

            members[i].activeBalance = staking.stakeLedger[i].activeBalance;
            members[i].pendingNominate = false;

            members[i].withdrawbleBalance = getWithdrawableBalance(staking.stakeLedger[i], _eraId);
        }

        distributeRewards(_rewardsBalance);
    }
    /**
    * @dev Return relay chain stash account addresses
    */
    function getStakeAccounts(uint64 _eraId) public override view returns (bytes32[] memory){
        bytes32[] memory _stake = new bytes32[](members.length);
        uint j = 0;
        for (uint i = 0; i < members.length; i++) {
            if (members[i].startEra <= _eraId) {
                _stake[j] = members[i].stashAccount;
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
        for (uint i = 0; i < members.length; i++) {
            total += members[i].lockedStashBalance + members[i].freeStashBalance;
        }
        return total;
    }

    function _getTotalPooledKSM() internal view override returns (uint256) {
        //vKSM.balanceOf(address(this));
        // todo cache _getStashBalance value
        return _bufferedBalance.add(_getStashBalance()).add(_transientUpward);
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
