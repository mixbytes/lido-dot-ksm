// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Types.sol";

interface IOracleMaster {
    function addLedger(address _ledger) external;

    function removeLedger(address _ledger) external;

    function getOracle(address _ledger) view external returns (address);

    function setRelayParams(uint64 _relayGenesisTs, uint64 _relaySecondsPerEra) external;
}