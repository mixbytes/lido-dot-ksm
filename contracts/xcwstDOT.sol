// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "../interfaces/ILido.sol";
import "../interfaces/ILocalAsset.sol";
import "../interfaces/IAuthManager.sol";

contract xcwstDOT is Pausable {
    // LIDO contract
    ILido public LIDO;

    // xcDOT precompile
    IERC20 public XCDOT;

    // Local Asset address
    LocalAsset public XC20;

    // General oracle manager role
    bytes32 internal constant ROLE_PAUSE_MANAGER = keccak256("ROLE_PAUSE_MANAGER");

    // Beacon manager role
    bytes32 internal constant ROLE_BEACON_MANAGER = keccak256("ROLE_BEACON_MANAGER");

    // Allows function calls only from member with specific role
    modifier auth(bytes32 role) {
        require(IAuthManager(LIDO.AUTH_MANAGER()).has(role, msg.sender), "XCWSTKSM: UNAUTHOROZED");
        _;
    }

    /**
     * @param _lido address of the stDOT token to wrap
     * @param _xcDOT address of the xcDOT token
     */
    function initialize(ILido _lido, IERC20 _xcDOT) external {
        require(address(_xcDOT) != address(0), "XCWSTDOT: BAD_LIDO_ADDRESS");
        require(address(_lido) != address(0), "XCWSTDOT: BAD_XCDOT_ADDRESS");
        require(address(LIDO) == address(0), "XCWSTDOT: ALREADY_INITIALIZED");
        LIDO = _lido;
        XCDOT = _xcDOT;
    }

    /**
    * @notice Stub fallback for native token
    */
    receive() payable external {}

    /**
    * @notice Stop wrap/unwrap, allowed to call only by ROLE_PAUSE_MANAGER
    */
    function pause() external auth(ROLE_PAUSE_MANAGER) {
        _pause();
    }

    /**
    * @notice Resume wrap/unwrap, allowed to call only by ROLE_PAUSE_MANAGER
    */
    function resume() external auth(ROLE_PAUSE_MANAGER) {
        _unpause();
    }

    /**
     * @param _xc20 address of the local asset
     * @param name name for the local asset
     * @param symbol symbol for the local asset
     * @param decimals decimals for the local asset
     */
    function setLocalAsset(
        LocalAsset _xc20, 
        string calldata name, 
        string calldata symbol, 
        uint8 decimals) 
    external auth(ROLE_BEACON_MANAGER) {
        require(address(_xc20) != address(0), "XCWSTDOT: BAD_XC20_ADDRESS");
        require(address(XC20) == address(0), "XCWSTDOT: XC20_ALREADY_SETTED");
        XC20 = _xc20;
        XC20.set_metadata(name, symbol, decimals);
    }

    /**
     * @notice Stake xcDOT to stDOT and wrap stDOT to xcwstDOT
     * @param _xcDOTAmount amount of xcDOT
     * @return Amount of xcwstDOT for a given xcDOT amount
     */
    function submit(uint256 _xcDOTAmount) external whenNotPaused returns (uint256) {
        require(_xcDOTAmount > 0, "XCWSTDOT: ZERO_XCDOT");
        XCDOT.transferFrom(msg.sender, address(this), _xcDOTAmount);
        if (XCDOT.allowance(address(this), address(LIDO)) < _xcDOTAmount) {
            XCDOT.approve(address(LIDO), type(uint256).max);
        }
        uint256 shares = LIDO.deposit(_xcDOTAmount);
        require(shares > 0, "XCWSTDOT: ZERO_SHARES");
        XC20.mint(msg.sender, shares);
        return shares;
    }

    /**
     * @notice Wrap stDOT to xcwstDOT
     * @param _stDOTAmount amount of stDOT
     * @return Amount of xcwstDOT for a given stDOT amount
     */
    function wrap(uint256 _stDOTAmount) external whenNotPaused returns (uint256) {
        require(_stDOTAmount > 0, "XCWSTDOT: ZERO_STDOT");
        uint256 wstDOTAmount = LIDO.getSharesByPooledKSM(_stDOTAmount);
        require(wstDOTAmount > 0, "XCWSTDOT: MINT_ZERO_AMOUNT");
        require(LIDO.transferFrom(msg.sender, address(this), _stDOTAmount), "XCWSTDOT: TRANSFER_FROM_REVERT");
        XC20.mint(msg.sender, wstDOTAmount);
        return wstDOTAmount;
    }

    /**
     * @notice Unwrap xcwstDOT to stDOT
     * @param _wstDOTAmount amount of xcwstDOT
     * @return Amount of stDOT for a given xcwstDOT amount
     */
    function unwrap(uint256 _wstDOTAmount) external whenNotPaused returns (uint256) {
        require(_wstDOTAmount > 0, "XCWSTDOT: ZERO_WSTDOT");
        uint256 stDOTAmount = LIDO.getPooledKSMByShares(_wstDOTAmount);
        require(stDOTAmount > 0, "XCWSTDOT: BURN_ZERO_AMOUNT");
        XC20.burn(msg.sender, _wstDOTAmount);
        require(LIDO.transfer(msg.sender, stDOTAmount), "XCWSTDOT: TRANSFER_REVERT");
        return stDOTAmount;
    }

    /**
     * @notice Get amount of xcwstDOT for a given amount of stDOT
     * @param _stDOTAmount amount of stDOT
     * @return Amount of xcwstDOT for a given stDOT amount
     */
    function getWstKSMByStKSM(uint256 _stDOTAmount) external view returns (uint256) {
        return LIDO.getSharesByPooledKSM(_stDOTAmount);
    }

    /**
     * @notice Get amount of stDOT for a given amount of xcwstDOT
     * @param _wstDOTAmount amount of xcwstDOT
     * @return Amount of stDOT for a given xcwstDOT amount
     */
    function getStKSMByWstKSM(uint256 _wstDOTAmount) external view returns (uint256) {
        return LIDO.getPooledKSMByShares(_wstDOTAmount);
    }
}