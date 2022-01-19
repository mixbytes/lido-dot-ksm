// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../interfaces/IOracleMaster.sol";
import "../interfaces/ILedgerFactory.sol";
import "../interfaces/ILedger.sol";
import "../interfaces/IController.sol";
import "../interfaces/IAuthManager.sol";

import "./stKSM.sol";


library WithdrawalQueue {
    struct Batch {
        uint256 amount;
        uint256 totalShares;
    }

    struct Queue {
        Batch[] items;
        uint256[] ids;

        uint256 first;
        uint256 size;
        uint256 cap;
    }

    function init(Queue storage queue, uint256 cap) external {
        queue.items = new Batch[](cap);
        queue.ids = new uint256[](cap);
        queue.first = 0;
        queue.size = 0;
        queue.cap = cap;
    }

    function push(Queue storage queue, Batch memory elem) external returns(uint256 _id) {
        require(queue.size < queue.cap, "WithdrawalQueue: capacity exceeded");
        queue.items[(first + queue.size + 1) % queue.cap] = elem;
        _id = queue.ids[(first + queue.size) % queue.cap] + 1;
        queue.ids[(first + queue.size + 1) % queue.cap] = _id;
        queue.size++;
    }

    function pop(Queue storage queue) external returns(Batch memory _item, uint256 _id) {
        _item = queue.items[first];
        _id = queue.ids[first];
        first = (first + 1) % queue.cap;
        queue.size--;
    }

    function top(Queue storage queue) external view returns(Batch memory _item, uint256 _id) {
        _item = queue.items[first];
        _id = queue.ids[first];
    }

    function last(Queue storage queue) external view returns(Batch memory _item, uint256 _id) {
        _item = queue.items[(first + queue.size) % queue.cap];
        _id = queue.ids[(first + queue.size) % queue.cap];
    }

    function size(Queue storage queue) external view returns(uint256 _size) {
        _size = queue.size;
    }

    function cap(Queue storage queue) external view returns(uint256 _cap) {
        _cap = queue.cap;
    }

    function nextId(Queue storage queue) external view returns(uint256 _id) {
        _id = queue.ids[(first + queue.size) % queue.cap] + 1;
    }
}

contract Withdrawal {
    // stKSM smart contract
    IERC20 public stKSM;

    // stKSM smart contract
    IERC20 public xcKSM;

    // withdrawal queue
    WithdrawalQueue.Queue public queue;

    // ready to claim xcKSMs per batch id
    mapping(uint256 => uint256) public readyToClaim;

    struct Request {
        uint256 share;
        uint256 batchId;
    }

    // user's withdrawal requests (unclaimed)
    mapping(address => Request[]) public userRequests;

    // buffered redeems
    uint256 public bufferedRedeems;

    // buffered redeem total shares
    uint256 public bufferedTotalShares;

    // xcKSMs for claim sum
    uint256 public unclaimedSum;

    // batches sum
    uint256 public batchesSum;


    modifier onlyLido() {
        _;
    }


    function newEra() external onlyLido {
        WithdrawalQueue.Batch memory newBatch = Batch(bufferedRedeems, bufferedTotalShares);
        queue.push(newBatch);

        batchesSum += bufferedRedeems;
        bufferedRedeems = 0;
        bufferedTotalShares = 0;

        WithdrawalQueue.Batch memory oldBatch = queue.top();
        uint256 freeTokens = xcKSM.balanceOf(address(this)) - unclaimedSum;
        uint256 needToUnbondBatch = stKSM.balanceOf(address(this)) * oldBatch.amount / batchesSum; // XXX: rebase to actual stKSM amount required to unbond this batch

        if (freeTokens >= needToUnbondBatch) {
            // remove batch
            // batchesSum -= oldBatch.amount;
        }

        // TODO check actual stKSMs amount calculation
    }

    function redeem(address from, uint256 amount) external onlyLido {
        stKSM.transferFrom(address(stKSM), address(this), amount);
        uint256 userShares = toShares(amount);
        bufferedTotalShares += userShares;
        bufferedRedeems += amount;

        Claim memory claim = Claim(userShares, queue.nextId());
        userRequests[from].push(claim);
    }

    function claim(address who) external onlyLido {
        // go through claims and check if unlocked than just transfer xcKSMs
    }

    // TODO view func to calc avalilable to claim and waiting amount
    function getRedeemStatus() external view returns(uint256 _waiting, uint256 _available) {
        return (0, 0);
    }

    function toShares(uint256 tokens) internal view returns(uint256) {
        if (bufferedTotalShares > 0) {
            return tokens * bufferedRedeems / bufferedTotalShares;
        }
        else {
            return tokens;
        }
    }

}
