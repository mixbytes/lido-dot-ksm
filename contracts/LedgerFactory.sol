// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./proxy/LedgerProxy.sol";
import "../interfaces/ILedger.sol";

contract LedgerFactory {
    // LIDO address
    address private immutable LIDO;

    // Ledger beacon address
    address private immutable LEDGER_BEACON;

    constructor(address _lido, address _ledgerBeacon) {
        require(_lido != address(0), "LF: LIDO_ZERO_ADDRESS");
        require(_ledgerBeacon != address(0), "LF: BEACON_ZERO_ADDRESS");

        LIDO = _lido;
        LEDGER_BEACON = _ledgerBeacon;
    }

    /**
    * @notice Create new ledger proxy contract
    */
    function createLedger(
        bytes32 _stashAccount,
        bytes32 _controllerAccount,
        address _vKSM,
        address _controller,
        uint128 _minNominatorBalance
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
                    LIDO
                )
            )
        );

        return ledger;
    }
}