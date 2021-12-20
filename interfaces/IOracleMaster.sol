// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOracleMaster {
    function addLedger(address ledger) external;

    function removeLedger(address ledger) external;

    function getOracle(address ledger) view external returns (address);

    function eraId() view external returns (uint64);

    function setRelayParams(uint64 relayGenesisTs, uint64 relaySecondsPerEra) external;

    function setLido(address lido) external;
}