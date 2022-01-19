// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../interfaces/ILido.sol";


library WithdrawalQueue {
    struct Batch {
        uint256 eraStKSMShares; // Sum of stKSM shares for specific era
        uint256 eraTotalShares; // Sum of pool shares for specific era
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
        queue.items = new Batch[](cap);
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
    function push(Queue storage queue, Batch memory elem) external returns(uint256 _id) {
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
    function pop(Queue storage queue) external returns(Batch memory _item, uint256 _id) {
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
    * @notice Return first element of the queue
    * @param queue current queue
    */
    function top(Queue storage queue) external view returns(Batch memory _item, uint256 _id) {
        _item = queue.items[queue.first];
        _id = queue.ids[queue.first];
    }

    /**
    * @notice Return last element of the queue
    * @param queue current queue
    */
    function last(Queue storage queue) external view returns(Batch memory _item, uint256 _id) {
        _item = queue.items[(queue.first + queue.size - 1) % queue.cap];
        _id = queue.ids[(queue.first + queue.size - 1) % queue.cap];
    }

    /**
    * @notice Return last element id + 1
    * @param queue current queue
    */
    function nextId(Queue storage queue) external view returns(uint256 _id) {
        _id = queue.ids[(queue.first + queue.size - 1) % queue.cap] + 1;
    }
}

contract Withdrawal is Initializable {
    using WithdrawalQueue for WithdrawalQueue.Queue;

    // stKSM smart contract
    ILido public stKSM;

    // withdrawal queue
    WithdrawalQueue.Queue public queue;

    // batch id => price for pool shares to xcKSM 
    // to retrive xcKSM amount for user: user_pool_shares * readyToClaim[batch_id]
    mapping(uint256 => uint256) public batchXcKSMPrice;

    struct Request {
        uint256 share;
        uint256 batchId;
    }

    // user's withdrawal requests (unclaimed)
    mapping(address => Request[]) public userRequests;

    // total stKSM shares amount on contract
    uint256 public totalStKSMShares;

    // stKSM shares amount for era
    uint256 public eraStKSMShares;

    // pool shares for era
    uint256 public eraPoolShares;

    // total amount of pool shares
    uint256 public totalPoolShares;

    // Last Id of queue element which can be claimed
    uint256 public claimableId;


    modifier onlyLido() {
        require(msg.sender == address(stKSM), "WITHDRAWAL: CALLER_NOT_LIDO");
        _;
    }

    /**
    * @notice Initialize redeemPool contract.
    * @param _stKSM - stKSM address
    * @param _cap - cap for queue
    */
    function initialize(
        address _stKSM,
        uint256 _cap
    ) external initializer {
        require(_stKSM != address(0), "WITHDRAWAL: INCORRECT_STKSM_ADDRESS");
        stKSM = ILido(_stKSM);
        queue.init(_cap);
    }

    /**
    * @notice Burn pool shares from first element of queue and move index for allow claiming. After that add new batch
    */
    function newEra() external onlyLido returns (uint256) {
        uint256 sharesForBurn;

        if (queue.size == queue.cap) {
            (WithdrawalQueue.Batch memory topBatch, uint256 topId) = queue.top();
            // batchKSMPrice = stKSM_price_to_KSM * (stKSM_shares / pool_shares)
            // when user try to claim: user_KSM = user_pool_share * batchKSMPrice
            batchXcKSMPrice[topId] = getCurrentPoolSharePrice();
            queue.pop();
            totalPoolShares -= topBatch.eraTotalShares;
            sharesForBurn = topBatch.eraStKSMShares;
            totalStKSMShares -= topBatch.eraStKSMShares;
            claimableId = topId;
        }

        WithdrawalQueue.Batch memory newBatch = WithdrawalQueue.Batch(eraStKSMShares, eraPoolShares);
        queue.push(newBatch);

        eraStKSMShares = 0;
        eraPoolShares = 0;

        // TODO: this amount of stKSM shares must be burned on Lido
        return sharesForBurn;
    }

    /**
    * @notice Mint pool shares for user according to current exchange rate
    * @param _from user address for minting
    * @param _amount amount of stKSM which user wants to redeem
    */
    function redeem(address _from, uint256 _amount) external onlyLido {
        uint256 stKSMShares = stKSM.getSharesByPooledKSM(_amount);
        stKSM.transferFrom(address(stKSM), address(this), _amount);
        
        // they should burned only after removing queue element
        uint256 userShares = toShares(stKSMShares);
        eraPoolShares += userShares;
        totalPoolShares += userShares;

        totalStKSMShares += stKSMShares;
        eraStKSMShares += stKSMShares;

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
                readyToClaim += requests[i].share * batchXcKSMPrice[requests[i].batchId] / 10**12;
                readyToClaimCount += 1;
            }
            else {
                requests[i - readyToClaimCount] = requests[i];
            }
        }

        // remove claimed items
        for (uint256 i = 0; i < readyToClaimCount; ++i) { requests.pop(); }

        return readyToClaim;
    }

    /**
    * @notice Check available for claim xcKSM balance for user
    * @param _holder user address
    */
    function getRedeemStatus(address _holder) external view returns(uint256 _waiting, uint256 _available) {
        Request[] storage requests = userRequests[_holder];

        for (uint256 i = 0; i < requests.length; ++i) {
            if (requests[i].batchId < claimableId) {
                _available += requests[i].share * batchXcKSMPrice[requests[i].batchId] / 10**12;
            }
            else {
                _waiting += requests[i].share * getCurrentPoolSharePrice() / 10**12;
            }
        }
        return (_waiting, _available);
    }

    /**
    * @notice Calculate current pool share to xcKSM price
    */
    function getCurrentPoolSharePrice() public view returns (uint256) {
        uint256 batchKSMPrice;
        if (totalPoolShares > 0) {
            batchKSMPrice = stKSM.getPooledKSMByShares(10**12) * totalStKSMShares / totalPoolShares;
        }
        return batchKSMPrice;
    }

    /**
    * @notice Calculate pool share for given stKSM shares amount
    * @param _tokens amount of stKSM shares
    */
    function toShares(uint256 _tokens) internal view returns(uint256) {
        if (totalPoolShares > 0) {
            return _tokens * totalStKSMShares / totalPoolShares;
        }
        else {
            return _tokens;
        }
    }
}
