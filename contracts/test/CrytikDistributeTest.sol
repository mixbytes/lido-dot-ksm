// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "../Lido.sol";

contract Mock {
    fallback() external {
        revert();
    }
}

contract Lido2Test is Lido {
    //bool private distributeFail;

    modifier auth(bytes32 role) override {
        revert("AUTH");
        _;
    }

    constructor(){
        ORACLE_MASTER = msg.sender;

        address mock = address(0); //address(new Mock());
        initialize(mock, mock, mock, mock, mock, mock);
        configure(mock, 50_000_000_000_000);
    }

    //function crytic_test_distribute() public view returns (bool){
    //    return !distributeFail;
    //}

    function crytic_balance_invariant() public view returns (bool){
        uint256 totalLedgerBalance = 0;
        for(uint i=0; i<ledgers.length; i++){
            address l = ledgers[i];
            totalLedgerBalance+=ledgerStake[l];
        }
        return _getTotalPooledKSM() + bufferedRedeems - bufferedDeposits == totalLedgerBalance;
    }

    function __redeem(uint256 amount) external {
        require(amount <= _getTotalPooledKSM());

        uint256 _shares = getSharesByPooledKSM(amount);
        _burnShares(msg.sender, _shares);

        fundRaisedBalance -= amount;
        bufferedRedeems += amount;
    }

    function __deposit(uint256 amount) external {
        _submit(amount);
    }

    function __distribute() external {
        (bool success, bytes memory data) = address(this).call(abi.encodeWithSelector(Lido2Test.softRebalanceStakes.selector));
        assert(success);
    }

    function softRebalanceStakes() external {
        _softRebalanceStakes();
    }

    function configure(address mock, uint256 totalStake) internal {
        require(totalShares < uint256(type(uint128).max) );
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

contract  Fake {
    uint256 private inner;

    function setInner(uint256 _inner) external{
        if(_inner == 1){
            return;
        }
        inner = _inner;
    }

    function increase() external {
        assert(inner!=0xFFFFFFFF);
    }

    function crytic_never_occur() public view returns (bool){
        return inner!=1;
    }

    function crytic_set_inner_revert(uint256 _inner) public returns (bool){
        return true;
    }

}

