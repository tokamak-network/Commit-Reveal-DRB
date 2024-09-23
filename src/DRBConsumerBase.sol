// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDRBCoordinator} from "./interfaces/IDRBCoordinator.sol";

/**
 * @notice Interface for contracts using VRF randomness
 * @dev USAGE
 *
 * @dev Consumer contracts must inherit from DRBConsumerBase, and can
 * @dev initialize Coordinator address in their constructor as
 */
abstract contract DRBConsumerBase {
    error OnlyCoordinatorCanFulfill(address have, address want);
    error InvalidRequest(uint256 requestId);

    /// @dev The DRBCoordinator contract
    IDRBCoordinator internal immutable i_drbCoordinator;

    /**
     * @param drbCoordinator The address of the DRBCoordinator contract
     */
    constructor(address drbCoordinator) {
        i_drbCoordinator = IDRBCoordinator(drbCoordinator);
    }

    receive() external payable {}

    /**
     * @return requestId The ID of the request
     * @dev Request Randomness from the Coordinator
     */
    function _requestRandomNumber(uint32 callbackGasLimit) internal returns (uint256 requestId) {
        requestId = i_drbCoordinator.requestRandomNumber{value: msg.value}(callbackGasLimit);
    }

    /**
     * @param round The round of the randomness
     * @param randomNumber The random number
     * @dev Callback function for the Coordinator to call after the request is fulfilled.  Override this function in your contract
     */
    function _fulfillRandomWords(uint256 round, uint256 randomNumber) internal virtual;

    /**
     * @param requestId The round of the randomness
     * @param randomNumber The random number
     * @dev Callback function for the Coordinator to call after the request is fulfilled. This function is called by the Coordinator
     */
    function rawFulfillRandomWords(uint256 requestId, uint256 randomNumber) external {
        require(
            msg.sender == address(i_drbCoordinator), OnlyCoordinatorCanFulfill(msg.sender, address(i_drbCoordinator))
        );
        _fulfillRandomWords(requestId, randomNumber);
    }

    function getRefund(uint256 requestId) external {
        i_drbCoordinator.getRefund(requestId);
    }
}
