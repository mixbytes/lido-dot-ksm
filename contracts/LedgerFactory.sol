// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./proxy/LedgerProxy.sol";
import "../interfaces/ILedger.sol";

contract LedgerFactory {
    // LIDO address
    address private immutable LIDO;

    // Ledger beacon address
    address private immutable LEDGER_BEACON;

    /**
    * @notice Constructor
    * @param _lido - LIDO address
    * @param _ledgerBeacon - ledger beacon address
    */
    constructor(address _lido, address _ledgerBeacon) {
        require(_lido != address(0), "LF: LIDO_ZERO_ADDRESS");
        require(_ledgerBeacon != address(0), "LF: BEACON_ZERO_ADDRESS");

        LIDO = _lido;
        LEDGER_BEACON = _ledgerBeacon;
    }

    /**
    * @notice Create new ledger proxy contract
    * @param _stashAccount - stash account address on relay chain
    * @param _controllerAccount - controller account on relay chain
    * @param _vKSM - vKSM contract address
    * @param _controller - xcmTransactor(relaychain calls relayer) contract address
    * @param _minNominatorBalance - minimal allowed nominator balance
    * @param _minimumBalance - minimal allowed active balance for ledger
    * @param _maxUnlockingChunks - maximum amount of unlocking chunks
    */
    function createLedger(
        bytes32 _stashAccount,
        bytes32 _controllerAccount,
        address _vKSM,
        address _controller,
        uint128 _minNominatorBalance,
        uint128 _minimumBalance,
        uint256 _maxUnlockingChunks
    ) external returns (address) {
        require(msg.sender == LIDO, "LF: ONLY_LIDO");

        address ledger = address(
            new LedgerProxy(
                LEDGER_BEACON, 
                abi.encodeWithSelector(
                    ILedger.initialize.selector,
                    _stashAccount,
                    _controllerAccount,
                    _vKSM,
                    _controller,
                    _minNominatorBalance,
                    LIDO,
                    _minimumBalance,
                    _maxUnlockingChunks
                )
            )
        );

        return ledger;
    }
}