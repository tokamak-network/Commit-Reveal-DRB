// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DRBCoordinatorStorage} from "./DRBCoordinatorStorage.sol";
import {ReentrancyGuardTransient} from "./utils/ReentrancyGuardTransient.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OptimismL1Fees} from "./OptimismL1Fees.sol";
import {DRBConsumerBase} from "./DRBConsumerBase.sol";
import {IDRBCoordinator} from "./interfaces/IDRBCoordinator.sol";
import { console } from "lib/forge-std/src/console.sol";

/// @title DRBCoordinator, distributed random beacon coordinator, using commit-reveal scheme
/// @author Justin G

contract DRBCoordinator is Ownable, ReentrancyGuardTransient, IDRBCoordinator, DRBCoordinatorStorage, OptimismL1Fees {
    /// *** Functions ***

    /**
     * @notice Initializes the contract with specified parameters.
     * @dev The constructor sets the activation threshold, flat fee, and compensate amount.
     *      It also assigns the owner of the contract to the deployer's address.
     * @param activationThreshold The minimum amount required to activate the contract.
     * @param flatFee The flat fee to be charged for transactions.
     * @param compensateAmount The amount to be compensated in certain conditions.
     */
    constructor(uint256 activationThreshold, uint256 flatFee, uint256 compensateAmount) Ownable(msg.sender) {
        s_activationThreshold = activationThreshold;
        s_flatFee = flatFee;
        s_compensateAmount = compensateAmount;
    }

    /// ** Consumer Interface **


/**
 * @notice Requests a random number from the system.
 * @dev This function allows external users to request a random number by 
 *      providing a callback gas limit and a sufficient amount of Ether.
 * @param callbackGasLimit The gas limit for the callback function.
 * @return round The current round number for this request.
 */
    function requestRandomNumber(uint32 callbackGasLimit) external payable nonReentrant returns (uint256 round) {
        require(callbackGasLimit <= MAX_CALLBACK_GAS_LIMIT, ExceedCallbackGasLimit());
        require(s_activatedOperators.length > 2, NotEnoughActivatedOperators());
        require(msg.value >= _calculateRequestPrice(callbackGasLimit, tx.gasprice), InsufficientAmount());
        unchecked {
            round = s_nextRound++;
        }
        uint256 requestAndRefundCost = _calculateGetRequestAndRefundCost(tx.gasprice);
        uint256 minDepositForThisRound =
            _calculateMinDepositForOneRound(callbackGasLimit, tx.gasprice) + requestAndRefundCost;
        s_requestInfo[round] = RequestInfo({
            consumer: msg.sender,
            requestedTime: block.timestamp,
            cost: msg.value,
            callbackGasLimit: callbackGasLimit,
            minDepositForOperator: minDepositForThisRound,
            requestAndRefundCost: requestAndRefundCost
        });
        address[] memory activatedOperators;
        s_activatedOperatorsAtRound[round] = activatedOperators = s_activatedOperators;
        uint256 activatedOperatorsLength = activatedOperators.length;
        uint256 i;
        mapping(address => uint256) storage activatedOperatorOrderAtRound = s_activatedOperatorOrderAtRound[round];
        uint256 activationThreshold = s_activationThreshold;
        do {
            address operator = activatedOperators[i];
            activatedOperatorOrderAtRound[operator] = i;
            uint256 activatedOperatorIndex = s_activatedOperatorOrder[operator];
            if ((s_depositAmount[operator] -= minDepositForThisRound) < activationThreshold) {
                console.log("Operator getting deactivated while requesting random number is", operator);
                _deactivate(activatedOperatorIndex, operator);
            }
            unchecked {
                ++i;
            }
        } while (i < activatedOperatorsLength);
        console.log("s_drbCoordinator.getActivatedOperatorIndex(s_operatorAddresses[i])", s_activatedOperatorOrder[address(0x717e6a320cf44b4aFAc2b0732D9fcBe2B7fa0Cf6)]);
        emit RandomNumberRequested(round, activatedOperators);
    }

    /**
     * @notice Allows consumers to request a refund for their request.
     * @dev This function refunds the cost of the request under certain conditions.
     * 
     * The conditions for a refund are as follows:
     * 1. A few minutes have passed without any commit after a random number was requested.
     * 2. The commit phase is over and there are less than 2 commits.
     * 3. The reveal phase is over and at least one participant hasn't revealed.
     *
     * @param round The request ID for which the refund is being requested.
     */
    function getRefund(uint256 round) external nonReentrant {
        require(msg.sender == s_requestInfo[round].consumer, NotConsumer());
        uint256 ruleNum = 3;
        uint256 commitEndTime = s_roundInfo[round].commitEndTime;
        uint256 commitLength = s_commits[round].length;
        uint256 revealLength = s_reveals[round].length;
        if (block.timestamp > s_requestInfo[round].requestedTime + MAX_WAIT && commitLength == 0) {
            ruleNum = 0;
        } else if (commitLength > 0) {
            if (commitLength < 2 && block.timestamp > commitEndTime) {
                ruleNum = 1;
            } else if (block.timestamp > commitEndTime + REVEAL_DURATION && revealLength < commitLength) {
                ruleNum = 2;
            }
        }
        require(ruleNum != 3, NotRefundable());

        uint256 activatedOperatorsAtRoundLength = s_activatedOperatorsAtRound[round].length;

        if (ruleNum == 0) {
            uint256 totalSlashAmount = activatedOperatorsAtRoundLength * s_requestInfo[round].minDepositForOperator;
            payable(msg.sender).transfer(totalSlashAmount + s_requestInfo[round].cost);
        } else {
            uint256 requestRefundTxCostAndCompensateAmount =
                s_requestInfo[round].requestAndRefundCost + s_compensateAmount;
            uint256 refundAmount = s_requestInfo[round].cost + requestRefundTxCostAndCompensateAmount;
            uint256 minDepositAtRound = s_requestInfo[round].minDepositForOperator;
            uint256 activationThreshold = s_activationThreshold;

            if (ruleNum == 1) {
                uint256 returnAmountForCommitted = minDepositAtRound
                    + (
                        (
                            (activatedOperatorsAtRoundLength - commitLength) * minDepositAtRound
                                - requestRefundTxCostAndCompensateAmount
                        ) / commitLength
                    );
                for (uint256 i; i <= activatedOperatorsAtRoundLength; i = _unchecked_inc(i)) {
                    address operator = s_activatedOperatorsAtRound[round][i];
                    if (s_commitOrder[round][operator] != 0) {
                        _checkAndActivateIfNotForceDeactivated(
                            s_activatedOperatorOrder[operator],
                            s_depositAmount[operator] += returnAmountForCommitted,
                            activationThreshold,
                            operator
                        );
                    }
                }
            } else {
                uint256 returnAmountForRevealed = minDepositAtRound
                    + (
                        ((commitLength - revealLength) * minDepositAtRound - requestRefundTxCostAndCompensateAmount)
                            / revealLength
                    );
                for (uint256 i; i <= activatedOperatorsAtRoundLength; i = _unchecked_inc(i)) {
                    address operator = s_activatedOperatorsAtRound[round][i];
                    if (s_revealOrder[round][operator] != 0) {
                        _checkAndActivateIfNotForceDeactivated(
                            s_activatedOperatorOrder[operator],
                            s_depositAmount[operator] += returnAmountForRevealed,
                            activationThreshold,
                            operator
                        );
                    }
                }
            }
            payable(msg.sender).transfer(refundAmount);
        }
        emit Refund(round);
    }

    /**
     * @notice Calculates the price for a request based on the provided gas limit.
     * @param callbackGasLimit The gas limit to be used for the callback function.
     * @return The calculated request price as a uint256.
     */
    function calculateRequestPrice(uint256 callbackGasLimit) external view returns (uint256) {
        return _calculateRequestPrice(callbackGasLimit, tx.gasprice);
    }

    /**
     * @notice Estimates the price of a request based on the given gas limit and gas price.
     * @param callbackGasLimit The maximum amount of gas that can be used for the callback function.
     * @param gasPrice The price of gas in wei, used to calculate the overall request price.
     * @return The estimated price of the request in wei.
     */
    function estimateRequestPrice(uint256 callbackGasLimit, uint256 gasPrice) external view returns (uint256) {
        return _calculateRequestPrice(callbackGasLimit, gasPrice);
    }

    /**
     * @notice Estimates the minimum deposit required for one round of requests.
     * @param callbackGasLimit The maximum amount of gas that can be used for the callback.
     * @param gasPrice The current gas price to be used for the estimation.
     * @return The estimated minimum deposit required for one round.
     */
    function estimateMinDepositForOneRound(uint256 callbackGasLimit, uint256 gasPrice)
        external
        view
        returns (uint256)
    {
        return _calculateMinDepositForOneRound(callbackGasLimit, gasPrice) + _calculateGetRequestAndRefundCost(gasPrice);
    }

    /**
     * @notice Checks if the operator can be activated based on their deposit amount and activation status.
     * @param activatedOperatorIndex The index of the currently activated operator.
     * @param updatedDepositAmount The amount of deposit the operator has updated.
     * @param minDepositForThisRound The minimum required deposit amount for this round.
     * @param operator The address of the operator to check and potentially activate.
     */
    function _checkAndActivateIfNotForceDeactivated(
        uint256 activatedOperatorIndex,
        uint256 updatedDepositAmount,
        uint256 minDepositForThisRound,
        address operator
    ) private {
        if (
            activatedOperatorIndex == 0 && updatedDepositAmount >= minDepositForThisRound
                && !s_forceDeactivated[operator]
        ) {
            console.log("Activating the operator", operator);
            _activate(operator);
        }
    }

    /**
     * @notice Calculates the total request price based on the callback gas limit and gas price.
     *         Takes into account only 2 commits and reveal
     * @param callbackGasLimit The maximum amount of gas that can be used for the callback.
     * @param gasPrice The price of gas in Wei.
     * @return The total request price in Wei.
     */
    function _calculateRequestPrice(uint256 callbackGasLimit, uint256 gasPrice) private view returns (uint256) {
        return (((gasPrice * (callbackGasLimit + TWOCOMMIT_TWOREVEAL_GASUSED)) * (s_premiumPercentage + 100)) / 100)
            + s_flatFee + _getL1CostWeiForCalldataSize(TWOCOMMIT_TWOREVEAL_CALLDATA_BYTES_SIZE);
    }

    /**
     * @notice Calculates the minimum deposit required for one round.
     * @param callbackGasLimit The gas limit for the callback function.
     * @param gasPrice The current price of gas in wei.
     * @return The minimum deposit required for one round in wei.
     */
    function _calculateMinDepositForOneRound(uint256 callbackGasLimit, uint256 gasPrice)
        private
        view
        returns (uint256)
    {
        return (((gasPrice * (callbackGasLimit + ONECOMMIT_ONEREVEAL_GASUSED)) * (s_premiumPercentage + 100)) / 100)
            + s_flatFee + _getL1CostWeiForCalldataSize(ONECOMMIT_ONEREVEAL_CALLDATA_BYTES_SIZE) + s_compensateAmount;
    }

    /**
     * @notice Calculates the total cost for a get request and refund.
     * @param gasPrice The price of gas in wei.
     * @return The total cost in wei for the get request and refund.
     */
    function _calculateGetRequestAndRefundCost(uint256 gasPrice) private view returns (uint256) {
        return (((gasPrice * MAX_REQUEST_REFUND_GASUSED) * (s_premiumPercentage + 100)) / 100)
            + _getL1CostWeiForCalldataSize(REQUEST_REFUND_CALLDATA_BYTES_SIZE);
    }

    /// ** Operator(Node) Interface **

    /**
     * @notice Commits a value for a specific round by an activated operator.
     * @param round The round number for which the commit is being made.
     * @param a The hashed value of the secret being committed (as a bytes32).
     */
    function commit(uint256 round, bytes32 a) external {
        address[] storage activatedOperatorsAtRound = s_activatedOperatorsAtRound[round];
        require(
            activatedOperatorsAtRound[s_activatedOperatorOrderAtRound[round][msg.sender]] == msg.sender,
            WasNotActivated()
        );
        bytes32[] storage commits = s_commits[round];
        RoundInfo storage roundInfo = s_roundInfo[round];
        mapping(address => uint256) storage commitOrder = s_commitOrder[round];
        uint256 commitLength = commits.length;
        if (commitLength == 0) {
            roundInfo.commitEndTime = block.timestamp + COMMIT_DURATION;
        } else {
            require(block.timestamp <= roundInfo.commitEndTime, CommitPhaseOver());
            require(commitOrder[msg.sender] == 0, AlreadyCommitted());
        }
        commits.push(a);
        unchecked {
            ++commitLength;
        }
        commitOrder[msg.sender] = commitLength;
        if (commitLength == activatedOperatorsAtRound.length) {
            roundInfo.commitEndTime = block.timestamp;
        }
        emit Commit(msg.sender, round);
    }

    /**
     * @notice Reveals a commitment for a specified round.
     * @param round The round number for which the commit is being revealed.
     * @param s The secret value being revealed.
     */
    function reveal(uint256 round, bytes32 s) external {
        uint256 commitOrder = s_commitOrder[round][msg.sender];
        require(commitOrder != 0, NotCommitted());
        mapping(address => uint256) storage revealOrder = s_revealOrder[round];
        require(revealOrder[msg.sender] == 0, AlreadyRevealed());
        RoundInfo storage roundInfo = s_roundInfo[round];
        bytes32[] storage commits = s_commits[round];
        bytes32[] storage reveals = s_reveals[round];
        uint256 commitEndTime = roundInfo.commitEndTime;
        uint256 commitLength = commits.length;
        require(
            (block.timestamp > commitEndTime && block.timestamp <= commitEndTime + REVEAL_DURATION), NotRevealPhase()
        );
        require(keccak256(abi.encodePacked(s)) == commits[commitOrder - 1], RevealValueMismatch());
        reveals.push(s);
        uint256 revealLength = revealOrder[msg.sender] = reveals.length;
        if (revealLength == commitLength) {
            uint256 randomNumber = uint256(keccak256(abi.encodePacked(reveals)));
            roundInfo.randomNumber = randomNumber;
            RequestInfo storage requestInfo = s_requestInfo[round];
            bool success = _call(
                requestInfo.consumer,
                abi.encodeWithSelector(DRBConsumerBase.rawFulfillRandomWords.selector, round, randomNumber),
                requestInfo.callbackGasLimit
            );
            roundInfo.fulfillSucceeded = success;
            uint256 minDepositForThisRound = requestInfo.minDepositForOperator;
            uint256 minDepositWithReward = requestInfo.cost / revealLength + minDepositForThisRound;
            uint256 activationThreshold = s_activationThreshold;
            uint256 activatedOperatorsAtRoundLength = s_activatedOperatorsAtRound[round].length - 1;
            for (uint256 i = 1; i <= activatedOperatorsAtRoundLength; i = _unchecked_inc(i)) {
                address operator = s_activatedOperatorsAtRound[round][i];
                _checkAndActivateIfNotForceDeactivated(
                    s_activatedOperatorOrder[operator],
                    s_depositAmount[operator] +=
                        (revealOrder[operator] != 0 ? minDepositWithReward : minDepositForThisRound),
                    activationThreshold,
                    operator
                );
            }
        }
        emit Reveal(msg.sender, round);
    }

    /**
     * @notice Allows users to deposit Ether into the contract.
     * @dev This function is marked as non-reentrant to prevent reentrancy attacks. 
     *      It calls the internal `_deposit()` function to handle the actual deposit logic.
     */
    function deposit() external payable nonReentrant {
        _deposit();
    }

    /**
     * @notice Allows users to deposit Ether and activate their account.
     * @dev This function is marked as non-reentrant to prevent reentrancy attacks.
     *      It calls the internal functions `_deposit()` & `_activate()` to 
     *      handle the deposit logic
     */
    function depositAndActivate() external payable nonReentrant {
        _deposit();
        _activate(msg.sender);
    }

    /**
     * @notice Withdraws a specified amount of Ether from the caller's account.
     * @dev This function checks if the caller's deposit amount is sufficient to cover the withdrawal.
     *      If the deposit amount falls below the activation threshold after withdrawal,
     *      the operator will be deactivated.
     * @param amount The amount of Ether to withdraw, specified in wei.
     */
    function withdraw(uint256 amount) external nonReentrant {
        s_depositAmount[msg.sender] -= amount;
        uint256 activatedOperatorIndex = s_activatedOperatorOrder[msg.sender];
        if (activatedOperatorIndex != 0 && s_depositAmount[msg.sender] < s_activationThreshold) {
            _deactivate(activatedOperatorIndex, msg.sender);
        }
        payable(msg.sender).transfer(amount);
    }

    /**
     * @notice Activates the caller's account.
     * @dev This function can only be called by an external user. 
     * If the caller's account is marked as deactivated, it will be reactivated.
     */
    function activate() external nonReentrant {
        if (s_forceDeactivated[msg.sender]) {
            s_forceDeactivated[msg.sender] = false;
        }
        _activate(msg.sender);
    }

    /**
     * @notice Deactivates the caller's operator status.
     * @dev This function marks the caller as deactivated, preventing further operations.
     * It can only be called if the caller has not already been force deactivated.
     */
    function deactivate() external nonReentrant {
        require(s_forceDeactivated[msg.sender] == false, AlreadyForceDeactivated());
        s_forceDeactivated[msg.sender] = true;
        uint256 activatedOperatorIndex = s_activatedOperatorOrder[msg.sender];
        if (activatedOperatorIndex != 0) {
            _deactivate(activatedOperatorIndex, msg.sender);
        }
    }

    /**
     * @notice Activates an operator if they meet the necessary conditions.
     * @dev This function checks if the operator has already been activated,
     *      verifies that the operator's deposit meets the activation threshold,
     *      and ensures the maximum number of activated operators has not been reached.
     * @param operator The address of the operator to be activated.
     */
    function _activate(address operator) private {
        require(s_activatedOperatorOrder[operator] == 0, AlreadyActivated());
        require(s_depositAmount[operator] >= s_activationThreshold, InsufficientDeposit());

        uint256 activatedOperatorLength = s_activatedOperators.length;
        require(activatedOperatorLength < MAX_ACTIVATED_OPERATORS, ACTIVATED_OPERATORS_LIMIT_REACHED());

        s_activatedOperators.push(operator);
        s_activatedOperatorOrder[operator] = activatedOperatorLength + 1;
        emit Activated(operator);
    }

    /**
     * @notice Increases the deposit amount for the caller.
     */
    function _deposit() private {
        s_depositAmount[msg.sender] = s_depositAmount[msg.sender] + msg.value;
        emit AmountDeposited(msg.value, msg.sender);
    }

    /**
     * @notice Deactivates an operator by its index and updates the state accordingly.
     * @dev This function removes the operator from the list of activated operators,
     *      replaces it with the last operator in the array, and updates the order mapping.
     * @param activatedOperatorIndex The index of the operator to deactivate in the array.
     * @param operator The address of the operator to deactivate.
     */
    function _deactivate(uint256 activatedOperatorIndex, address operator) private {
        if(s_activatedOperators.length != 1){
            address lastOperator = s_activatedOperators[s_activatedOperators.length - 1];
            s_activatedOperators[activatedOperatorIndex - 1] = lastOperator;
            s_activatedOperatorOrder[lastOperator] = activatedOperatorIndex;
        }
        s_activatedOperators.pop();
        delete s_activatedOperatorOrder[operator];
        emit DeActivated(operator);
    }

    /**
     * @notice Executes a low-level call to a target contract.
     * @param target The address of the contract to call.
     * @param data The data to send with the call, encoded as bytes.
     * @param callbackGasLimit The maximum amount of gas to forward to the target contract.
     * @return success A boolean indicating whether the call was successful.
     */
    function _call(address target, bytes memory data, uint256 callbackGasLimit) private returns (bool success) {
        assembly {
            let g := gas()
            // Compute g -= GAS_FOR_CALL_EXACT_CHECK and check for underflow
            // The gas actually passed to the callee is min(gasAmount, 63//64*gas available)
            // We want to ensure that we revert if gasAmount > 63//64*gas available
            // as we do not want to provide them with less, however that check itself costs
            // gas. GAS_FOR_CALL_EXACT_CHECK ensures we have at least enough gas to be able to revert
            // if gasAmount > 63//64*gas available.
            if lt(g, GAS_FOR_CALL_EXACT_CHECK) { revert(0, 0) }
            g := sub(g, GAS_FOR_CALL_EXACT_CHECK)
            // if g - g//64 <= gas
            // we subtract g//64 because of EIP-150
            g := sub(g, div(g, 64))
            if iszero(gt(sub(g, div(g, 64)), callbackGasLimit)) { revert(0, 0) }
            // solidity calls check that a contract actually exists at the destination, so we do the same
            if iszero(extcodesize(target)) { revert(0, 0) }
            // call and return whether we succeeded. ignore return data
            // call(gas, addr, value, argsOffset,argsLength,retOffset,retLength)
            success := call(callbackGasLimit, target, 0, add(data, 0x20), mload(data), 0, 0)
        }
        return success;
    }

    /**
     * @notice Increments the given unsigned integer by one without overflow checks.
     * @param a The unsigned integer to increment.
     * @return The incremented value of `a`.
     */
    function _unchecked_inc(uint256 a) private pure returns (uint256) {
        unchecked {
            return a + 1;
        }
    }

    /// ** Owner Interface **

    /**
     * @notice Sets the premium percentage for the contract.
     * @param premiumPercentage The new premium percentage to be set.
     */
    function setPremiumPercentage(uint256 premiumPercentage) external onlyOwner {
        s_premiumPercentage = premiumPercentage;
        emit PremiumPercentageUpdated(premiumPercentage);
    }

    /**
     * @notice Sets the flat fee for the contract.
     * @param flatFee The new flat fee to be set.
     */
    function setFlatFee(uint256 flatFee) external onlyOwner {
        s_flatFee = flatFee;
        emit FlatFeeUpdated(flatFee);
    }

    /**
     * @notice Sets the activation threshold for the contract.
     * @param activationThreshold The new activation threshold value to be set.
     */
    function setActivationThreshold(uint256 activationThreshold) external onlyOwner {
        s_activationThreshold = activationThreshold;
        emit ActivationThresholdUpdated(activationThreshold);
    }

    /**
     * @notice Sets the compensation amount for the contract.
     * @param compensateAmount The new compensation amount to be set.
     */
    function setCompensations(uint256 compensateAmount) external onlyOwner {
        s_compensateAmount = compensateAmount;
        emit CompensationAmountUpdated(compensateAmount);
    }
}
