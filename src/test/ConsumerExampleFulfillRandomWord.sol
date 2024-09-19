// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {IDRBCoordinator} from "../interfaces/IDRBCoordinator.sol";

contract ConsumerExampleFulfillRandomWord {
    struct RequestStatus {
        bool requested; // whether the request has been made
        bool fulfilled; // whether the request has been successfully fulfilled
        uint256 randomNumber;
    }

    mapping(uint256 => RequestStatus)
        public s_requests; /* requestId --> requestStatus */

    // past requests Id.
    uint256[] public requestIds;
    address s_owner;
    uint32 public constant CALLBACK_GAS_LIMIT = 83011;

    error OnlyCoordinatorCanFulfill(address have, address want);
    error InvalidRequest(uint256 requestId);

    /// @dev The RNGCoordinator contract
    IDRBCoordinator internal immutable i_drbCoordinator;

    constructor(address rngCoordinator) {
        s_owner = msg.sender;
        i_drbCoordinator = IDRBCoordinator(rngCoordinator);
        for (uint256 i; i < 10; i++) {
            s_requests[i].requested = true;
        }
    }

    function rawFulfillRandomWords(
        uint256 requestId,
        uint256 randomNumber
    ) external {
        require(
            msg.sender == s_owner,
            OnlyCoordinatorCanFulfill(msg.sender, address(i_drbCoordinator))
        );
        fulfillRandomWords(requestId, randomNumber);
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256 hashedOmegaVal
    ) internal {
        if (!s_requests[requestId].requested) {
            revert InvalidRequest(requestId);
        }
        s_requests[requestId].fulfilled = true;
        s_requests[requestId].randomNumber = hashedOmegaVal;
    }
}
