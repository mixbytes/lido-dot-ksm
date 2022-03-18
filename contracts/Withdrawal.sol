// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./utils/WithdrawalQueue.sol";
import "../interfaces/ILido.sol";

contract Withdrawal is Initializable {
    using WithdrawalQueue for WithdrawalQueue.Queue;

    // Element removed from queue
    event ElementRemoved(uint256 elementId);

    // Element added to queue
    event ElementAdded(uint256 elementId);

    // New redeem request added
    event RedeemRequestAdded(address indexed user, uint256 shares, uint256 batchId);

    // xcKSM claimed by user
    event Claimed(address indexed user, uint256 claimedAmount);

    // Losses ditributed to contract
    event LossesDistributed(uint256 losses);

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

    // stKSM(xcKSM) virtual amount for batch
    uint256 public batchVirtualXcKSMAmount;

    // Last Id of queue element which can be claimed
    uint256 public claimableId;

    // Balance for claiming
    uint256 public pendingForClaiming;

    // max amount of requests in parallel
    uint16 internal constant MAX_REQUESTS = 20;


    modifier onlyLido() {
        require(msg.sender == address(stKSM), "WITHDRAWAL: CALLER_NOT_LIDO");
        _;
    }

    /**
    * @notice Initialize redeemPool contract.
    * @param _cap - cap for queue
    * @param _xcKSM - xcKSM precompile address
    */
    function initialize(
        uint256 _cap,
        address _xcKSM
    ) external initializer {
        require(_cap > 0, "WITHDRAWAL: INCORRECT_CAP");
        require(_xcKSM != address(0), "WITHDRAWAL: INCORRECT_XCKSM_ADDRESS");
        queue.init(_cap);
        xcKSM = IERC20(_xcKSM);
    }

    /**
    * @notice Set stKSM contract address, allowed to only once
    * @param _stKSM stKSM contract address
    */
    function setStKSM(address _stKSM) external {
        require(address(stKSM) == address(0), "WITHDRAWAL: STKSM_ALREADY_DEFINED");
        require(_stKSM != address(0), "WITHDRAWAL: INCORRECT_STKSM_ADDRESS");

        stKSM = ILido(_stKSM);
    }

    /**
    * @notice Burn pool shares from first element of queue and move index for allow claiming. After that add new batch
    */
    function newEra() external onlyLido {
        uint256 newXcKSMAmount = xcKSM.balanceOf(address(this)) - pendingForClaiming;

        if ((newXcKSMAmount > 0) && (queue.size > 0)) {
            (WithdrawalQueue.Batch memory topBatch, uint256 topId) = queue.top();
            // batchSharePrice = pool_xcKSM_balance / pool_shares
            // when user try to claim: user_KSM = user_pool_share * batchSharePrice
            uint256 sharePriceForBatch = getBatchSharePrice(topBatch);
            uint256 xcKSMForBatch = topBatch.batchTotalShares * sharePriceForBatch / 10**12;
            if (newXcKSMAmount >= xcKSMForBatch) {
                batchSharePrice[topId] = sharePriceForBatch;

                totalXcKSMPoolShares -= topBatch.batchXcKSMShares;
                totalVirtualXcKSMAmount -= xcKSMForBatch;
                if (totalXcKSMPoolShares == 0) {
                    totalVirtualXcKSMAmount = 0;
                }

                claimableId = topId;
                pendingForClaiming += xcKSMForBatch;

                queue.pop();

                emit ElementRemoved(topId);
            }
        }

        if ((batchVirtualXcKSMAmount > 0) && (queue.size < queue.cap)) {
            uint256 batchKSMPoolShares = getKSMPoolShares(batchVirtualXcKSMAmount);

            // NOTE: batch total shares = batch xcKSM amount, because 1 share = 1 xcKSM
            WithdrawalQueue.Batch memory newBatch = WithdrawalQueue.Batch(batchVirtualXcKSMAmount, batchKSMPoolShares);
            uint256 newId = queue.push(newBatch);

            totalVirtualXcKSMAmount += batchVirtualXcKSMAmount;
            totalXcKSMPoolShares += batchKSMPoolShares;

            batchVirtualXcKSMAmount = 0;

            emit ElementAdded(newId);
        }
    }

    /**
    * @notice Returns total virtual xcKSM balance of contract for which losses can be applied
    */
    function totalBalanceForLosses() external view returns (uint256) {
        return totalVirtualXcKSMAmount + batchVirtualXcKSMAmount;
    }

    /**
    * @notice 1. Mint equal amount of pool shares for user 
    * @notice 2. Adjust current amount of virtual xcKSM on Withdrawal contract
    * @notice 3. Burn shares on LIDO side
    * @param _from user address for minting
    * @param _amount amount of stKSM which user wants to redeem
    */
    function redeem(address _from, uint256 _amount) external onlyLido {
        // NOTE: user share in batch = user stKSM balance in specific batch
        require(userRequests[_from].length < MAX_REQUESTS, "WITHDRAWAL: REQUEST_CAP_EXCEEDED");
        batchVirtualXcKSMAmount += _amount;

        Request memory req = Request(_amount, queue.nextId());
        userRequests[_from].push(req);

        emit RedeemRequestAdded(_from, req.share, req.batchId);
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
            if (requests[i].batchId <= claimableId) {
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

        emit Claimed(_holder, readyToClaim);

        return readyToClaim;
    }

    /**
    * @notice Apply losses to current stKSM shares on this contract
    * @param _losses user address for claiming
    */
    function ditributeLosses(uint256 _losses) external onlyLido {
        totalVirtualXcKSMAmount -= _losses;
        emit LossesDistributed(_losses);
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
            // user_xcKSM = user_batch_share * batch_share_price
            // batch_share_price = (1 / batch_total_shares) * batch_pool_shares * (total_xcKSM / total_pool_shares)
            if (_batch.batchTotalShares > 0) {
                batchKSMPrice = (10**12 * _batch.batchXcKSMShares * totalVirtualXcKSMAmount) / 
                                (_batch.batchTotalShares * totalXcKSMPoolShares);
            }
            else {
                // NOTE: This means that batch not added to queue currently
                if (batchVirtualXcKSMAmount > 0) {
                    batchKSMPrice = (10**12 * getKSMPoolShares(batchVirtualXcKSMAmount) * totalVirtualXcKSMAmount) / 
                                    (batchVirtualXcKSMAmount * totalXcKSMPoolShares);
                }
            }
        }
        else {
            // NOTE: This means that we have only one batch that no in the pool (batch share price == 10**12)
            if (batchVirtualXcKSMAmount > 0) {
                batchKSMPrice = 10**12;
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
            return _amount * totalXcKSMPoolShares / totalVirtualXcKSMAmount;
        }
        return _amount;
    }
}
