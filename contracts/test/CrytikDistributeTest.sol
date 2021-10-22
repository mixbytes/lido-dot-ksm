// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "../Lido.sol";

contract Lido2Test is Distribute {
    bool private distributeFail;

    event DistributeFailed();

    constructor(){
        test_configure(50_000_000_000_000);
    }

    function crytic_test_distribute() public view returns (bool){
        return !distributeFail;
    }

    function crytic_distribute_invariant() public view returns (bool){
        uint256 totalLedgerBalance = 0;
        for (uint i = 0; i < ledgers.length; i++) {
            address l = ledgers[i];
            totalLedgerBalance += ledgerStake[l];
        }
        return _getTotalPooledKSM() + bufferedRedeems - bufferedDeposits == totalLedgerBalance;
    }

    function test__redeem(uint256 amount) external {
        _burn(amount);
    }

    function test__deposit(uint256 amount) external {
        _submit(amount);
    }

    function test__distribute() external {
        (bool success,) = address(this).call(abi.encodeWithSelector(Lido2Test.softRebalanceStakes.selector));
        if (!success) {
            emit DistributeFailed();
            distributeFail = true;
        }
    }

    function echidna_test() public view returns (bool) {
        return !distributeFail;
    }

    function softRebalanceStakes() external {
        _distribute();
    }

    function test_configure(uint256 totalStake) internal {
        require(totalShares < uint256(type(uint128).max));
        // configuration of 4 ledgers with shares are equal to 100
        ledgers.push(address(0x01));
        ledgers.push(address(0x02));
        ledgers.push(address(0x03));
        ledgers.push(address(0x04));

        ledgerByAddress[address(0x01)] = 1;
        ledgerByAddress[address(0x02)] = 2;
        ledgerByAddress[address(0x03)] = 3;
        ledgerByAddress[address(0x04)] = 4;

        ledgerShares[address(0x01)] = 100;
        ledgerShares[address(0x02)] = 100;
        ledgerShares[address(0x03)] = 100;
        ledgerShares[address(0x04)] = 100;

        ledgerSharesTotal = 400;

        // initial stake
        _submit(totalStake);

        // distribute equally between ledgers
        uint256 ledgerStakeBalance = totalStake / 4;
        ledgerStake[address(0x01)] = ledgerStakeBalance;
        ledgerStake[address(0x02)] = ledgerStakeBalance;
        ledgerStake[address(0x03)] = ledgerStakeBalance;
        ledgerStake[address(0x04)] = totalStake - (ledgerStakeBalance * 3);

        // and flush buffers
        bufferedDeposits = 0;
        bufferedRedeems = 0;
    }
}

