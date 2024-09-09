// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DRBCoordinatorStorage} from "./DRBCoordinatorStorage.sol";
import {ReentrancyGuardTransient} from "./utils/ReentrancyGuardTransient.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OptimismL1Fees} from "./OptimismL1Fees.sol";
import {DRBConsumerBase} from "./DRBConsumerBase.sol";
import {IDRBCoordinator} from "./interfaces/IDRBCoordinator.sol";

import {console2} from "forge-std/Test.sol";

/// @title DRBCoordinator, distributed random beacon coordinator, using commit-reveal scheme
/// @author Justin G

contract DRBCoordinator is
    Ownable,
    ReentrancyGuardTransient,
    IDRBCoordinator,
    DRBCoordinatorStorage,
    OptimismL1Fees
{
    /// *** Functions ***
    constructor(
        uint256 minDeposit,
        uint256[3] memory compensations
    ) Ownable(msg.sender) {
        s_minDeposit = minDeposit;
        s_compensations = compensations;
        s_activatedOperators.push(address(0)); // dummy data
    }

    /// ***
    /// ** Consumer Interface **
    function requestRandomNumber(
        uint32 callbackGasLimit
    ) external payable nonReentrant returns (uint256 round) {
        require(s_activatedOperators.length > 2, NotEnoughActivatedOperators());
        uint256 cost = _calculateRequestPrice(callbackGasLimit, tx.gasprice);
        uint256 minDeposit = _calculateMinDeposit(
            callbackGasLimit,
            tx.gasprice
        );
        require(msg.value >= cost, InsufficientAmount());
        unchecked {
            round = s_nextRound++;
        }
        s_requestInfo[round] = RequestInfo({
            consumer: msg.sender,
            requestedTime: block.timestamp,
            cost: msg.value,
            callbackGasLimit: callbackGasLimit,
            minDepositForOperator: minDeposit
        });
        address[] memory activatedOperators;
        s_activatedOperatorsAtRound[
            round
        ] = activatedOperators = s_activatedOperators;
        uint256 activatedOperatorsLength = activatedOperators.length;
        uint256 i = 1;
        do {
            address operator = activatedOperators[i];
            s_activatedOperatorOrderAtRound[round][operator] = i;
            uint256 activatedOperatorIndex = s_activatedOperatorOrder[operator];
            if ((s_depositAmount[operator] -= minDeposit) < s_minDeposit)
                _deactivate(activatedOperatorIndex, operator);
            unchecked {
                ++i;
            }
        } while (i < activatedOperatorsLength);
        emit RandomNumberRequested(round);
    }

    /// @dev refund the cost of the request
    /// @param round the request id
    /// Note: condition for refund
    /// 1. A few minutes have passed without any commit after random number requested
    /// 2. CommitPhase is over and there are less than 2 commits
    /// 3. RevealPhase is over and at least one person hasn't revealed.
    function getRefund(uint256 round) external nonReentrant {
        require(msg.sender == s_requestInfo[round].consumer, NotConsumer());
        uint256 commitEndTime = s_roundInfo[round].commitEndTime;
        uint256 activatedOperatorsAtRoundLength = s_activatedOperatorsAtRound[
            round
        ].length - 1;
        uint256 commitLength = s_commits[round].length;
        uint256 revealLength = s_reveals[round].length;
        uint256 ruleNum = 3;
        if (
            block.timestamp > s_requestInfo[round].requestedTime + MAX_WAIT &&
            commitLength == 0
        ) ruleNum = 0;
        else if (commitLength > 0) {
            if (commitLength < 2 && block.timestamp > commitEndTime)
                ruleNum = 1;
            else if (
                block.timestamp > commitEndTime + REVEAL_DURATION &&
                revealLength < commitLength
            ) ruleNum = 2;
        }
        require(ruleNum != 3, NotRefundable());

        uint256 minDepositAtRound = s_requestInfo[round].minDepositForOperator;
        uint256 compensateAmount = s_compensations[ruleNum];
        uint256 operatorReturnAmount = s_compensations[2] - compensateAmount;
        uint256 minDepositToBeOperator = s_minDeposit;

        if (ruleNum == 0) {
            uint256 rest = activatedOperatorsAtRoundLength *
                (minDepositAtRound - operatorReturnAmount);
            for (
                uint256 i = 1;
                i <= activatedOperatorsAtRoundLength;
                i = _unchecked_inc(i)
            ) {
                address operator = s_activatedOperatorsAtRound[round][i];
                if (
                    (s_depositAmount[operator] += operatorReturnAmount) >=
                    minDepositToBeOperator &&
                    s_activatedOperatorOrder[operator] == 0
                ) {
                    _activate(operator);
                }
            }
            payable(msg.sender).transfer(rest + s_requestInfo[round].cost);
        } else {
            uint256 refundTxCostAndCompAmount = _calculateGetRefundCost(
                tx.gasprice
            ) + compensateAmount;
            uint256 refundAmount = s_requestInfo[round].cost +
                refundTxCostAndCompAmount;
            if (ruleNum == 1) {
                uint256 uncommitedLength = activatedOperatorsAtRoundLength -
                    commitLength;
                uint256 rest = uncommitedLength *
                    (minDepositAtRound - operatorReturnAmount) -
                    refundTxCostAndCompAmount;
                uint256 distributedSlashedAmount = rest / commitLength;
                uint256 returnAmountForCommitted = minDepositAtRound +
                    distributedSlashedAmount;
                for (
                    uint256 i = 1;
                    i <= activatedOperatorsAtRoundLength;
                    i = _unchecked_inc(i)
                ) {
                    address operator = s_activatedOperatorsAtRound[round][i];
                    uint256 activatedOperatorIndex = s_activatedOperatorOrder[
                        operator
                    ];
                    bool isCommitted = s_commitOrder[round][operator] != 0;
                    if (isCommitted) {
                        uint256 updatedDepositAmount = s_depositAmount[
                            operator
                        ] += returnAmountForCommitted;
                        if (
                            activatedOperatorIndex == 0 &&
                            updatedDepositAmount >= minDepositToBeOperator
                        ) {
                            _activate(operator);
                        }
                    } else {
                        uint256 updatedDepositAmount = s_depositAmount[
                            operator
                        ] += operatorReturnAmount;
                        if (
                            activatedOperatorIndex == 0 &&
                            updatedDepositAmount >= minDepositToBeOperator
                        ) {
                            _activate(operator);
                        }
                    }
                }
                payable(msg.sender).transfer(refundAmount);
            } else {
                uint256 unrevealedLength = commitLength - revealLength;
                uint256 rest = unrevealedLength *
                    minDepositAtRound -
                    refundTxCostAndCompAmount;
                uint256 distributedSlashedAmount = rest / revealLength;
                uint256 returnAmountForRevealed = minDepositAtRound +
                    distributedSlashedAmount;
                for (
                    uint256 i = 1;
                    i <= activatedOperatorsAtRoundLength;
                    i = _unchecked_inc(i)
                ) {
                    address operator = s_activatedOperatorsAtRound[round][i];
                    uint256 activatedOperatorIndex = s_activatedOperatorOrder[
                        operator
                    ];
                    bool isRevealed = s_revealOrder[round][operator] != 0;
                    if (isRevealed) {
                        uint256 updatedDepositAmount = s_depositAmount[
                            operator
                        ] += returnAmountForRevealed;
                        if (
                            activatedOperatorIndex == 0 &&
                            updatedDepositAmount >= minDepositToBeOperator
                        ) {
                            _activate(operator);
                        }
                    }
                }
                payable(msg.sender).transfer(refundAmount);
            }
        }
    }

    function calculateRequestPrice(
        uint256 callbackGasLimit
    ) external view returns (uint256) {
        return _calculateRequestPrice(callbackGasLimit, tx.gasprice);
    }

    function estimateRequestPrice(
        uint256 callbackGasLimit,
        uint256 gasPrice
    ) external view returns (uint256) {
        return _calculateRequestPrice(callbackGasLimit, gasPrice);
    }

    /// @dev 2 commits, 2 reveals
    function _calculateRequestPrice(
        uint256 callbackGasLimit,
        uint256 gasPrice
    ) private view returns (uint256) {
        return
            (((gasPrice * (callbackGasLimit + L2_GASUSED_PER_ROUND)) *
                (s_premiumPercentage + 100)) / 100) +
            s_flatFee +
            _getL1CostWeiForCalldataSize(CALLDATA_SIZE_BYTES_PER_ROUND);
    }

    function _calculateMinDeposit(
        uint256 callbackGasLimit,
        uint256 gasPrice
    ) private view returns (uint256) {
        return
            (((gasPrice * (callbackGasLimit + L2_MIN_DEPOSIT_GASUSED)) *
                (s_premiumPercentage + 100)) / 100) +
            s_flatFee +
            _getL1CostWeiForCalldataSize(L2_MIN_DEPOSIT_CALLDATA_SIZE_BYTES) +
            s_compensations[2];
    }

    function _calculateGetRefundCost(
        uint256 gasPrice
    ) private view returns (uint256) {
        return
            (((gasPrice * L2_GETREFUND_GASUSED) * (s_premiumPercentage + 100)) /
                100) +
            _getL1CostWeiForCalldataSize(L2_GETREFUND_CALLDATA_SIZE_BYTES);
    }

    /// ***
    /// ** Operator(Node) Interface **

    function commit(uint256 round, bytes32 a) external {
        require(
            s_activatedOperatorsAtRound[round][
                s_activatedOperatorOrderAtRound[round][msg.sender]
            ] == msg.sender,
            WasNotActivated()
        );
        if (s_commits[round].length == 0) {
            s_roundInfo[round].commitEndTime =
                block.timestamp +
                COMMIT_DURATION;
        } else {
            require(
                block.timestamp <= s_roundInfo[round].commitEndTime,
                CommitPhaseOver()
            );
            require(s_commitOrder[round][msg.sender] == 0, AlreadyCommitted());
        }
        s_commits[round].push(a);
        uint256 commitLength = s_commits[round].length;
        s_commitOrder[round][msg.sender] = commitLength;
        if (commitLength == s_activatedOperatorsAtRound[round].length - 1) {
            s_roundInfo[round].commitEndTime = block.timestamp;
        }
    }

    function reveal(uint256 round, bytes32 s) external {
        uint256 commitOrder = s_commitOrder[round][msg.sender];
        require(commitOrder != 0, NotCommitted());
        require(s_revealOrder[round][msg.sender] == 0, AlreadyRevealed());
        uint256 commitEndTime = s_roundInfo[round].commitEndTime;
        uint256 activatedOperatorsAtRoundLength = s_activatedOperatorsAtRound[
            round
        ].length - 1;
        require(
            activatedOperatorsAtRoundLength == s_commits[round].length ||
                (block.timestamp > commitEndTime &&
                    block.timestamp <= commitEndTime + REVEAL_DURATION),
            NotRevealPhase()
        );
        require(
            keccak256(abi.encodePacked(s)) == s_commits[round][commitOrder - 1],
            RevealValueMismatch()
        );
        s_reveals[round].push(s);
        s_revealOrder[round][msg.sender] = s_reveals[round].length;
        if (s_reveals[round].length == activatedOperatorsAtRoundLength) {
            uint256 randomNumber = uint256(
                keccak256(abi.encodePacked(s_reveals[round]))
            );
            s_roundInfo[round].randomNumber = randomNumber;
            bool success = _call(
                s_requestInfo[round].consumer,
                abi.encodeWithSelector(
                    DRBConsumerBase.rawFulfillRandomWords.selector,
                    round,
                    randomNumber
                ),
                s_requestInfo[round].callbackGasLimit
            );
            s_roundInfo[round].fulfillSucceeded = success;
            uint256 cost = s_requestInfo[round].cost;
            uint256 dividedReward = cost /
                activatedOperatorsAtRoundLength +
                s_requestInfo[round].minDepositForOperator;
            for (
                uint256 i = 1;
                i < s_activatedOperatorsAtRound[round].length;
                i = _unchecked_inc(i)
            ) {
                address operator = s_activatedOperatorsAtRound[round][i];
                uint256 activatedOperatorIndex = s_activatedOperatorOrder[
                    operator
                ];
                uint256 updatedDepositAmount = s_depositAmount[
                    operator
                ] += dividedReward;
                if (
                    activatedOperatorIndex == 0 &&
                    updatedDepositAmount >= s_minDeposit
                ) {
                    _activate(operator);
                }
            }
        }
    }

    function deposit() external payable nonReentrant {
        _deposit();
    }

    function depositAndActivate() external payable nonReentrant {
        _deposit();
        _activate();
    }

    function withdraw(uint256 amount) external nonReentrant {
        s_depositAmount[msg.sender] -= amount;
        uint256 activatedOperatorIndex = s_activatedOperatorOrder[msg.sender];
        if (
            activatedOperatorIndex != 0 &&
            s_depositAmount[msg.sender] < s_minDeposit
        ) _deactivate(activatedOperatorIndex);
        payable(msg.sender).transfer(amount);
    }

    function activate() external nonReentrant {
        require(
            s_depositAmount[msg.sender] >= s_minDeposit,
            InsufficientDeposit()
        );
        _activate();
    }

    function deactivate() external nonReentrant {
        uint256 activatedOperatorIndex = s_activatedOperatorOrder[msg.sender];
        require(activatedOperatorIndex != 0, AlreadyDeactivated());
        _deactivate(activatedOperatorIndex);
    }

    function _activate() private {
        require(s_activatedOperatorOrder[msg.sender] == 0, AlreadyActivated());
        s_activatedOperatorOrder[msg.sender] = s_activatedOperators.length;
        s_activatedOperators.push(msg.sender);
        emit Activated(msg.sender);
    }

    function _activate(address operator) private {
        require(s_activatedOperatorOrder[operator] == 0, AlreadyActivated());
        s_activatedOperatorOrder[operator] = s_activatedOperators.length;
        s_activatedOperators.push(operator);
        emit Activated(operator);
    }

    function _deposit() private {
        uint256 totalAmount = s_depositAmount[msg.sender] + msg.value;
        require(totalAmount >= s_minDeposit, InsufficientAmount());
        s_depositAmount[msg.sender] = totalAmount;
    }

    function _deactivate(uint256 activatedOperatorIndex) private {
        address lastOperator = s_activatedOperators[
            s_activatedOperators.length - 1
        ];
        s_activatedOperators[activatedOperatorIndex] = lastOperator;
        s_activatedOperators.pop();
        s_activatedOperatorOrder[lastOperator] = activatedOperatorIndex;
        delete s_activatedOperatorOrder[msg.sender];
        emit DeActivated(msg.sender);
    }

    function _deactivate(
        uint256 activatedOperatorIndex,
        address operator
    ) private {
        address lastOperator = s_activatedOperators[
            s_activatedOperators.length - 1
        ];
        s_activatedOperators[activatedOperatorIndex] = lastOperator;
        s_activatedOperators.pop();
        s_activatedOperatorOrder[lastOperator] = activatedOperatorIndex;
        delete s_activatedOperatorOrder[operator];
        emit DeActivated(operator);
    }

    function _call(
        address target,
        bytes memory data,
        uint256 callbackGasLimit
    ) private returns (bool success) {
        assembly {
            let g := gas()
            // Compute g -= GAS_FOR_CALL_EXACT_CHECK and check for underflow
            // The gas actually passed to the callee is min(gasAmount, 63//64*gas available)
            // We want to ensure that we revert if gasAmount > 63//64*gas available
            // as we do not want to provide them with less, however that check itself costs
            // gas. GAS_FOR_CALL_EXACT_CHECK ensures we have at least enough gas to be able to revert
            // if gasAmount > 63//64*gas available.
            if lt(g, GAS_FOR_CALL_EXACT_CHECK) {
                revert(0, 0)
            }
            g := sub(g, GAS_FOR_CALL_EXACT_CHECK)
            // if g - g//64 <= gas
            // we subtract g//64 because of EIP-150
            g := sub(g, div(g, 64))
            if iszero(gt(sub(g, div(g, 64)), callbackGasLimit)) {
                revert(0, 0)
            }
            // solidity calls check that a contract actually exists at the destination, so we do the same
            if iszero(extcodesize(target)) {
                revert(0, 0)
            }
            // call and return whether we succeeded. ignore return data
            // call(gas, addr, value, argsOffset,argsLength,retOffset,retLength)
            success := call(
                callbackGasLimit,
                target,
                0,
                add(data, 0x20),
                mload(data),
                0,
                0
            )
        }
        return success;
    }

    function _unchecked_inc(uint256 a) private pure returns (uint256) {
        unchecked {
            return a + 1;
        }
    }

    /// ***
    /// ** Owner Interface **
    function setPremiumPercentage(
        uint256 premiumPercentage
    ) external onlyOwner {
        s_premiumPercentage = premiumPercentage;
    }

    function setFlatFee(uint256 flatFee) external onlyOwner {
        s_flatFee = flatFee;
    }

    function setMinDeposit(uint256 minDeposit) external onlyOwner {
        s_minDeposit = minDeposit;
    }

    function setCompensations(
        uint256[3] memory compensations
    ) external onlyOwner {
        s_compensations = compensations;
    }
}
