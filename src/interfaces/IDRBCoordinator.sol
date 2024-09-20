// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title Commit-Recover
 * @author Justin g
 * @notice This contract is for generating random number
 *    1. Finished: round not Started | recover the random number
 *    2. Commit: participants commit their value
 */
interface IDRBCoordinator {
    function requestRandomNumber(uint32 callbackGasLimit) external payable returns (uint256);

    function getRefund(uint256 requestId) external;
}
