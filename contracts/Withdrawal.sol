// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/ILido.sol";


library WithdrawalQueue {
    struct Batch {
        uint256 batchTotalShares; // Total shares amount for batch
        uint256 batchXcKSMShares; // Batch xcKSM shares in xcKSM pool
    }

    struct Queue {
        Batch[] items;
        uint256[] ids;

        uint256 first;
        uint256 size;
        uint256 cap;
    }

    /**
    * @notice Queue initialization
    * @param queue queue for initializing
    * @param cap max amount of elements in the queue
    */
    function init(Queue storage queue, uint256 cap) external {
        for (uint256 i = 0; i < cap; ++i) {
            queue.items.push(Batch(0, 0));
        }
        queue.ids = new uint256[](cap);
        queue.first = 0;
        queue.size = 0;
        queue.cap = cap;
    }

    /**
    * @notice Add element to the end of queue
    * @param queue current queue
    * @param elem element for adding
    */
    function push(Queue storage queue, Batch memory elem) external returns (uint256 _id) {
        require(queue.size < queue.cap, "WithdrawalQueue: capacity exceeded");
        queue.items[(queue.first + queue.size) % queue.cap] = elem;
        if ((queue.first + queue.size) != 0) {
            _id = queue.ids[(queue.first + queue.size - 1) % queue.cap] + 1;
        }
        else {
            _id = 1;
        }
        queue.ids[(queue.first + queue.size) % queue.cap] = _id;
        queue.size++;
    }

    /**
    * @notice Remove element from top of the queue
    * @param queue current queue
    */
    function pop(Queue storage queue) external returns (Batch memory _item, uint256 _id) {
        require(queue.size > 0, "WithdrawalQueue: queue is empty");
        _item = queue.items[queue.first];
        _id = queue.ids[queue.first];
        if (queue.size == 1) {
            queue.first = 0;    
        }
        else {
            queue.first = (queue.first + 1) % queue.cap;
        }
        queue.size--;
    }

    /**
    * @notice Return batch for specific index
    * @param queue current queue
    * @param index index of batch
    */
    function findBatch(Queue storage queue, uint256 index) external view returns (Batch memory _item) {
        uint256 start = queue.first;
        for (uint256 i = start; i < start + queue.size; ++i) {
            if (queue.ids[i] == index) {
                return queue.items[i];
            }
        }
        return Batch(0, 0);
    }

    /**
    * @notice Return first element of the queue
    * @param queue current queue
    */
    function top(Queue storage queue) external view returns (Batch memory _item, uint256 _id) {
        _item = queue.items[queue.first];
        _id = queue.ids[queue.first];
    }

    /**
    * @notice Return last element of the queue
    * @param queue current queue
    */
    function last(Queue storage queue) external view returns (Batch memory _item, uint256 _id) {
        _item = queue.items[(queue.first + queue.size - 1) % queue.cap];
        _id = queue.ids[(queue.first + queue.size - 1) % queue.cap];
    }

    /**
    * @notice Return last element id + 1
    * @param queue current queue
    */
    function nextId(Queue storage queue) external view returns (uint256 _id) {
        _id = queue.ids[(queue.first + queue.size - 1) % queue.cap] + 1;
    }
}

contract Withdrawal is Initializable {
    using WithdrawalQueue for WithdrawalQueue.Queue;

    // stKSM smart contract
    ILido public stKSM;

    // xcKSM precompile
    IERC20 public xcKSM;

    // withdrawal queue
    WithdrawalQueue.Queue public queue;

    // batch id => price for pool shares to xcKSM 
    // to retrive xcKSM amount for user: user_pool_shares * batchSharePrice[batch_id]
    mapping(uint256 => uint256) public batchSharePrice;

    struct Request {
        uint256 share;
        uint256 batchId;
    }

    // user's withdrawal requests (unclaimed)
    mapping(address => Request[]) public userRequests;

    // total virtual xcKSM amount on contract
    uint256 public totalVirtualXcKSMAmount;

    // total amount of xcKSM pool shares
    uint256 public totalXcKSMPoolShares;

    // stKSM(xcKSM) amount for era
    uint256 public eraVirtualXcKSMAmount;

    // batch total shares for era
    uint256 public eraBatchShares;

    // Last Id of queue element which can be claimed
    uint256 public claimableId;

    // Last saved xcKSM balance on contract
    uint256 public xcKSMTotalBalance;

    // Balance for claiming
    uint256 public pendingForClaiming;


    modifier onlyLido() {
        require(msg.sender == address(stKSM), "WITHDRAWAL: CALLER_NOT_LIDO");
        _;
    }

    /**
    * @notice Initialize redeemPool contract.
    * @param _stKSM - stKSM address
    * @param _cap - cap for queue
    * @param _xcKSM - xcKSM precompile address
    */
    function initialize(
        address _stKSM,
        uint256 _cap,
        address _xcKSM
    ) external initializer {
        require(_stKSM != address(0), "WITHDRAWAL: INCORRECT_STKSM_ADDRESS");
        stKSM = ILido(_stKSM);
        queue.init(_cap);
        xcKSM = IERC20(_xcKSM);
    }

    /**
    * @notice Burn pool shares from first element of queue and move index for allow claiming. After that add new batch
    */
    function newEra() external onlyLido {
        uint256 newXcKSMAmount = xcKSM.balanceOf(address(this)) - pendingForClaiming;

        if (newXcKSMAmount > xcKSMTotalBalance) {
            uint256 diff = newXcKSMAmount - xcKSMTotalBalance;
            (WithdrawalQueue.Batch memory topBatch, uint256 topId) = queue.top();
            // batchSharePrice = pool_xcKSM_balance / pool_shares
            // when user try to claim: user_KSM = user_pool_share * batchSharePrice
            uint256 sharePriceForBatch = getBatchSharePrice(topBatch);
            uint256 xcKSMForBatch = topBatch.batchTotalShares * sharePriceForBatch / 10**12;
            if (diff >= xcKSMForBatch) {
                batchSharePrice[topId] = sharePriceForBatch;

                totalXcKSMPoolShares -= topBatch.batchXcKSMShares;
                totalVirtualXcKSMAmount -= xcKSMForBatch;

                claimableId = topId;
                pendingForClaiming += xcKSMForBatch;

                queue.pop();
            }
        }

        if (queue.size == queue.cap) {
            // TODO: do smth (Maybe skip era and wait for transfers from relay chain)
        }

        if (eraVirtualXcKSMAmount > 0) {
            uint256 batchKSMPoolShares = getKSMPoolShares(eraVirtualXcKSMAmount);

            WithdrawalQueue.Batch memory newBatch = WithdrawalQueue.Batch(eraBatchShares, batchKSMPoolShares);
            queue.push(newBatch);

            totalVirtualXcKSMAmount += eraVirtualXcKSMAmount;
            totalXcKSMPoolShares += batchKSMPoolShares;

            eraVirtualXcKSMAmount = 0;
            eraBatchShares = 0;
        }

        xcKSMTotalBalance = newXcKSMAmount;
    }

    /**
    * @notice 1. Mint equal amount of pool shares for user 
    * @notice 2. Adjust current amount of virtual xcKSM on Withdrawal contract
    * @notice 3. Burn shares on LIDO side
    * @param _from user address for minting
    * @param _amount amount of stKSM which user wants to redeem
    */
    function redeem(address _from, uint256 _amount) external onlyLido {
        // TODO: shares amount on Lido side must be burned after this function
        // and fundRaisedBalance must be decreased
        uint256 userShares = stKSM.getSharesByPooledKSM(_amount);
        
        eraBatchShares += userShares;
        eraVirtualXcKSMAmount += _amount;

        Request memory req = Request(userShares, queue.nextId());
        userRequests[_from].push(req);
    }

    /**
    * @notice Returns available for claiming xcKSM amount for user
    * @param _holder user address for claiming
    */
    function claim(address _holder) external onlyLido returns (uint256) {
        // go through claims and check if unlocked than just transfer xcKSMs
        uint256 readyToClaim = 0;
        uint256 readyToClaimCount = 0;
        Request[] storage requests = userRequests[_holder];

        for (uint256 i = 0; i < requests.length; ++i) {
            if (requests[i].batchId < claimableId) {
                readyToClaim += requests[i].share * batchSharePrice[requests[i].batchId] / 10**12;
                readyToClaimCount += 1;
            }
            else {
                requests[i - readyToClaimCount] = requests[i];
            }
        }

        // remove claimed items
        for (uint256 i = 0; i < readyToClaimCount; ++i) { requests.pop(); }

        require(readyToClaim <= xcKSM.balanceOf(address(this)), "WITHDRAWAL: CLAIM_EXCEEDS_BALANCE");
        xcKSM.transfer(_holder, readyToClaim);
        pendingForClaiming -= readyToClaim;

        return readyToClaim;
    }

    /**
    * @notice Apply losses to current stKSM shares on this contract
    * @param _losses user address for claiming
    */
    function ditributeLosses(uint256 _losses) external onlyLido {
        // TODO: add check on LIDO that losses not exceeds balance
        totalVirtualXcKSMAmount -= _losses;
    }

    /**
    * @notice Check available for claim xcKSM balance for user
    * @param _holder user address
    */
    function getRedeemStatus(address _holder) external view returns(uint256 _waiting, uint256 _available) {
        Request[] storage requests = userRequests[_holder];

        for (uint256 i = 0; i < requests.length; ++i) {
            if (requests[i].batchId <= claimableId) {
                _available += requests[i].share * batchSharePrice[requests[i].batchId] / 10**12;
            }
            else {
                _waiting += requests[i].share * getBatchSharePrice(queue.findBatch(requests[i].batchId)) / 10**12;
            }
        }
        return (_waiting, _available);
    }

    /**
    * @notice Calculate share price to KSM for specific batch
    * @param _batch batch
    */
    function getBatchSharePrice(WithdrawalQueue.Batch memory _batch) internal view returns (uint256) {
        uint256 batchKSMPrice;
        if (totalXcKSMPoolShares > 0) {
            if (_batch.batchTotalShares > 0) {
                batchKSMPrice = (10**12 * _batch.batchXcKSMShares * totalVirtualXcKSMAmount) / 
                                (_batch.batchTotalShares * totalXcKSMPoolShares);
            }
            else {
                // NOTE: This means that batch not added to queue currently
                if (eraBatchShares > 0) {
                    batchKSMPrice = (10**12 * getKSMPoolShares(eraVirtualXcKSMAmount) * totalVirtualXcKSMAmount) / 
                                    (eraBatchShares * totalXcKSMPoolShares);
                }
            }
        }
        return batchKSMPrice;
    }

    /**
    * @notice Calculate shares amount in KSM pool for specific xcKSM amount
    * @param _amount amount of xcKSM tokens
    */
    function getKSMPoolShares(uint256 _amount) internal view returns (uint256) {
        if (totalVirtualXcKSMAmount > 0) {
            uint256 KSMShares = _amount * totalXcKSMPoolShares / totalVirtualXcKSMAmount;
            return KSMShares;
        }
        return _amount;
    }
}
