// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DRBConsumerBase} from "./DRBConsumerBase.sol";

contract ConsumerExample is DRBConsumerBase {
    struct RequestStatus {
        bool requested; // whether the request has been made
        bool fulfilled; // whether the request has been successfully fulfilled
        uint256 randomNumber;
    }

    mapping(uint256 => RequestStatus) public s_requests; /* requestId --> requestStatus */

    // past requests Id.
    uint256[] public requestIds;
    uint32 public constant CALLBACK_GAS_LIMIT = 83011;

    /**
     * @dev Initializes the contract by passing the coordinator address to the DRBConsumerBase constructor.
     * @param coordinator The address of the DRB coordinator contract.
     */
    constructor(address coordinator) DRBConsumerBase(coordinator) {}

    /**
     * @notice Requests a random number from the DRBCoordinator with a specified gas limit.
     * @dev This function sends a request for a random number and stores the requestId.
     *      The request is recorded as "requested" in the `s_requests` mapping, and
     *      the requestId is pushed into the `requestIds` array.
     */
    function requestRandomNumber() external payable {
        uint256 requestId = _requestRandomNumber(CALLBACK_GAS_LIMIT);
        s_requests[requestId].requested = true;
        requestIds.push(requestId);
    }

    /**
     * @notice Internal function to fulfill the randomness request.
     * @dev Overrides the base implementation to handle a specific request and store the fulfilled random number.
     * @param requestId The ID of the request that needs to be fulfilled.
     * @param hashedOmegaVal The hashed random value that is being assigned to the request.
     */
    function _fulfillRandomWords(uint256 requestId, uint256 hashedOmegaVal) internal override {
        if (!s_requests[requestId].requested) {
            revert InvalidRequest(requestId);
        }
        s_requests[requestId].fulfilled = true;
        s_requests[requestId].randomNumber = hashedOmegaVal;
    }

    /**
     * @notice Returns the address of the DRB (Distributed Randomness Beacon) coordinator.
     * @dev This function provides the address of the DRB coordinator stored in the contract.
     * @return The address of the DRB coordinator.
     */
    function getRNGCoordinator() external view returns (address) {
        return address(i_drbCoordinator);
    }

    /**
     * @notice Returns the status of a request by its ID.
     * @dev Fetches the request from the `s_requests` mapping and returns its status.
     * @param _requestId The unique ID of the request whose status is being retrieved.
     * @return requested A boolean indicating whether the request was initiated.
     * @return fulfilled A boolean indicating whether the request has been fulfilled.
     * @return randomNumber The random number generated for the request (if fulfilled).
     */
    function getRequestStatus(uint256 _requestId) external view returns (bool, bool, uint256) {
        RequestStatus memory request = s_requests[_requestId];
        return (request.requested, request.fulfilled, request.randomNumber);
    }

    /**
     * @notice Retrieves the total number of requests.
     * @dev This function returns the length of the `requestIds` array, 
     *      which represents the total number of requests.
     * @return requestCount The total number of requests.
     */
    function totalRequests() external view returns (uint256 requestCount) {
        requestCount = requestIds.length;
    }

    /**
     * @notice Retrieves the most recent request ID.
     * @dev This function returns the last element in the `requestIds` array.
     * @return requestId The ID of the last request made. Returns 0 if no requests have been made.
     */
    function lastRequestId() external view returns (uint256 requestId) {
        requestId = requestIds.length == 0 ? 0 : requestIds[requestIds.length - 1];
    }
}
