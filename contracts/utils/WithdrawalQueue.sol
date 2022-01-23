// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

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
        uint256 id;
    }

    /**
    * @notice Queue initialization
    * @param queue queue for initializing
    * @param cap max amount of elements in the queue
    */
    function init(Queue storage queue, uint256 cap) internal {
        for (uint256 i = 0; i < cap; ++i) {
            queue.items.push(Batch(0, 0));
        }
        queue.ids = new uint256[](cap);
        queue.first = 0;
        queue.size = 0;
        queue.size = 0;
        queue.cap = cap;
    }

    /**
    * @notice Add element to the end of queue
    * @param queue current queue
    * @param elem element for adding
    */
    function push(Queue storage queue, Batch memory elem) internal returns (uint256 _id) {
        require(queue.size < queue.cap, "WithdrawalQueue: capacity exceeded");
        queue.items[(queue.first + queue.size) % queue.cap] = elem;
        queue.id++;
        queue.ids[(queue.first + queue.size) % queue.cap] = queue.id;
        queue.size++;
        return queue.id;
    }

    /**
    * @notice Remove element from top of the queue
    * @param queue current queue
    */
    function pop(Queue storage queue) internal returns (Batch memory _item, uint256 _id) {
        require(queue.size > 0, "WithdrawalQueue: queue is empty");
        _item = queue.items[queue.first];
        _id = queue.ids[queue.first];
        queue.first = (queue.first + 1) % queue.cap;
        queue.size--;
    }

    /**
    * @notice Return batch for specific index
    * @param queue current queue
    * @param index index of batch
    */
    function findBatch(Queue storage queue, uint256 index) internal view returns (Batch memory _item) {
        uint256 startIndex = queue.ids[queue.first];
        if (index >= startIndex) {
            if ((index - startIndex) < queue.size) {
                return queue.items[(queue.first + (index - startIndex)) % queue.cap];
            }
        }
        return Batch(0, 0);
    }

    /**
    * @notice Return first element of the queue
    * @param queue current queue
    */
    function top(Queue storage queue) internal view returns (Batch memory _item, uint256 _id) {
        require(queue.size > 0, "WithdrawalQueue: queue is empty");
        _item = queue.items[queue.first];
        _id = queue.ids[queue.first];
    }

    /**
    * @notice Return last element of the queue
    * @param queue current queue
    */
    function last(Queue storage queue) internal view returns (Batch memory _item, uint256 _id) {
        require(queue.size > 0, "WithdrawalQueue: queue is empty");
        _item = queue.items[(queue.first + queue.size - 1) % queue.cap];
        _id = queue.ids[(queue.first + queue.size - 1) % queue.cap];
    }

    /**
    * @notice Return last element id + 1
    * @param queue current queue
    */
    function nextId(Queue storage queue) internal view returns (uint256 _id) {
        _id = queue.id + 1;
    }
}