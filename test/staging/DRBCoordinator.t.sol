// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DRBCoordinator} from "../../src/DRBCoordinator.sol";
import {DRBCoordinatorStorageTest} from "test/shared/DRBCoordinatorStorageTest.t.sol";
import {ConsumerExample} from "../../src/ConsumerExample.sol";

import {console2} from "forge-std/Test.sol";

contract DRBCoordinatorTest is DRBCoordinatorStorageTest {
    ConsumerExample s_consumerExample;

    function mine() public {
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
    }

    function setUp() public override {
        _setUp();
        s_consumerExample = new ConsumerExample(address(s_drbCoordinator));
    }

    function deposit(address operator) public {
        vm.startPrank(operator);
        s_drbCoordinator.deposit{value: s_activationThreshold}();
        assertEq(s_drbCoordinator.getDepositAmount(operator), s_activationThreshold);
        vm.stopPrank();
    }

    function test_Deposit() public {
        vm.stopPrank();
        deposit(s_operatorAddresses[0]);
        vm.startPrank(OWNER);
    }

    function test_5Deposits() public {
        vm.stopPrank();
        for (uint256 i = 0; i < s_operatorAddresses.length; i++) {
            deposit(s_operatorAddresses[i]);
        }
        vm.startPrank(OWNER);
    }

    function activate(address operator) public {
        vm.startPrank(operator);
        s_drbCoordinator.activate();
        vm.stopPrank();
        address[] memory activatedOperators = s_drbCoordinator.getActivatedOperators();
        assertEq(activatedOperators[s_drbCoordinator.getActivatedOperatorIndex(operator)], operator);
    }

    function test_5Activate() public {
        vm.stopPrank();
        for (uint256 i = 0; i < s_operatorAddresses.length; i++) {
            deposit(s_operatorAddresses[i]);
            activate(s_operatorAddresses[i]);
        }
        address[] memory activatedOperators = s_drbCoordinator.getActivatedOperators();
        assertEq(activatedOperators.length - 1, s_operatorAddresses.length);
        vm.startPrank(OWNER);
    }

    modifier make5Activate() {
        vm.stopPrank();
        for (uint256 i = 0; i < s_operatorAddresses.length; i++) {
            deposit(s_operatorAddresses[i]);
            activate(s_operatorAddresses[i]);
        }
        _;
    }

    function deactivate(address operator) public {
        address[] memory activatedOperatorsBefore = s_drbCoordinator.getActivatedOperators();
        vm.startPrank(operator);
        s_drbCoordinator.deactivate();
        vm.stopPrank();
        address[] memory activatedOperatorsAfter = s_drbCoordinator.getActivatedOperators();
        assertEq(s_drbCoordinator.getActivatedOperatorIndex(operator), 0, "index");
        assertEq(activatedOperatorsBefore.length - 1, activatedOperatorsAfter.length, "length");
    }

    function test_5Deactivate() public make5Activate {
        for (uint256 i = 0; i < s_operatorAddresses.length; i++) {
            deactivate(s_operatorAddresses[i]);
        }
        vm.startPrank(OWNER);
        address[] memory activatedOperators = s_drbCoordinator.getActivatedOperators();
        assertEq(activatedOperators.length, 1);
        assertEq(activatedOperators[0], address(0));
    }

    function test_RequestRandomNumber() public make5Activate {
        address consumer = s_consumerAddresses[0];
        vm.startPrank(consumer);

        uint256 callbackGasLimit = s_consumerExample.CALLBACK_GAS_LIMIT();
        uint256 cost = s_drbCoordinator.estimateRequestPrice(callbackGasLimit, tx.gasprice);
        s_consumerExample.requestRandomNumber{value: cost}();

        // ** assert on ConsumerExample
        uint256 requestId = s_consumerExample.lastRequestId();
        (bool requested, bool fulfilled, uint256 randomNumber) = s_consumerExample.getRequestStatus(requestId);
        assertEq(requested, true);
        assertEq(fulfilled, false);
        assertEq(randomNumber, 0);
        assertEq(requestId, 0);

        // ** assert on DRBCoordinator
        DRBCoordinator.RequestInfo memory requestInfo = s_drbCoordinator.getRequestInfo(requestId);
        address[] memory activatedOperatorsAtRound = s_drbCoordinator.getActivatedOperatorsAtRound(requestId);
        assertEq(requestInfo.consumer, address(s_consumerExample), "consumer");
        assertEq(requestInfo.cost, cost, "cost");
        assertEq(requestInfo.callbackGasLimit, callbackGasLimit, "callbackGasLimit");
        assertEq(activatedOperatorsAtRound.length, 6, "activatedOperators");

        for (uint256 i; i < s_operatorAddresses.length; i++) {
            uint256 depositAmount = s_drbCoordinator.getDepositAmount(s_operatorAddresses[i]);
            if (depositAmount < s_activationThreshold) {
                assertEq(s_drbCoordinator.getActivatedOperatorIndex(s_operatorAddresses[i]), 0);
            } else {
                assertEq(s_drbCoordinator.getActivatedOperatorIndex(s_operatorAddresses[i]), i + 1);
            }
        }
    }

    function requestRandomNumber() public {
        uint256 callbackGasLimit = s_consumerExample.CALLBACK_GAS_LIMIT();
        uint256 cost = s_drbCoordinator.estimateRequestPrice(callbackGasLimit, tx.gasprice);
        s_consumerExample.requestRandomNumber{value: cost}();
    }

    function checkBalanceInvariant() public view {
        uint256 balanceOfDRBCoordinator = address(s_drbCoordinator).balance;
        uint256 depositSum;
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            depositSum += s_drbCoordinator.getDepositAmount(s_operatorAddresses[i]);
        }
        assertEq(balanceOfDRBCoordinator, depositSum, "balanceOfDRBCoordinator invariant assertion");
    }

    function test_CommitReveal() public make5Activate {
        /// ** 1. requestRandomNumber
        requestRandomNumber();
        uint256 requestId = s_consumerExample.lastRequestId();

        /// ** 2. commit
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            address operator = s_operatorAddresses[i];
            vm.startPrank(operator);
            s_drbCoordinator.commit(requestId, keccak256(abi.encodePacked(i)));
            vm.stopPrank();
            mine();

            uint256 commitOrder = s_drbCoordinator.getCommitOrder(requestId, operator);
            assertEq(commitOrder, i + 1);
        }
        DRBCoordinator.RoundInfo memory roundInfo = s_drbCoordinator.getRoundInfo(requestId);
        bytes32[] memory commits = s_drbCoordinator.getCommits(requestId);
        assertEq(commits.length, 5);
        assertEq(roundInfo.randomNumber, 0);
        assertEq(roundInfo.fulfillSucceeded, false);

        /// ** 3. reveal
        mine();
        bytes32[] memory reveals = new bytes32[](s_operatorAddresses.length);
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            address operator = s_operatorAddresses[i];
            vm.startPrank(operator);
            s_drbCoordinator.reveal(requestId, bytes32(i));
            reveals[i] = bytes32(i);
            vm.stopPrank();

            uint256 revealOrder = s_drbCoordinator.getRevealOrder(requestId, operator);
            assertEq(revealOrder, i + 1);
        }
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(reveals)));
        bytes32[] memory revealsOnChain = s_drbCoordinator.getReveals(requestId);
        assertEq(revealsOnChain.length, 5);
        roundInfo = s_drbCoordinator.getRoundInfo(requestId);
        assertEq(roundInfo.randomNumber, randomNumber);
        assertEq(roundInfo.fulfillSucceeded, true);

        for (uint256 i; i < s_operatorAddresses.length; i++) {
            uint256 depositAmount = s_drbCoordinator.getDepositAmount(s_operatorAddresses[i]);
            if (depositAmount < s_activationThreshold) {
                assertEq(s_drbCoordinator.getActivatedOperatorIndex(s_operatorAddresses[i]), 0);
            } else {
                assertEq(s_drbCoordinator.getActivatedOperatorIndex(s_operatorAddresses[i]), i + 1);
            }
        }
        checkBalanceInvariant();

        /// ** run one more time
        requestRandomNumber();
        requestId = s_consumerExample.lastRequestId();
        for (uint256 i; i < 2; i++) {
            address operator = s_operatorAddresses[i];
            vm.startPrank(operator);
            s_drbCoordinator.commit(requestId, keccak256(abi.encodePacked(i)));
            vm.stopPrank();
        }
        vm.warp(block.timestamp + 301);
        mine();
        for (uint256 i; i < 2; i++) {
            address operator = s_operatorAddresses[i];
            vm.startPrank(operator);
            s_drbCoordinator.reveal(requestId, bytes32(i));
            vm.stopPrank();
        }

        checkBalanceInvariant();
    }

    /// Note: condition for refund
    /// 1. A few minutes have passed without any commit after random number requested
    /// 2. CommitPhase is over and there are less than 2 commits
    /// 3. RevealPhase is over and at least one person hasn't revealed.

    /// rule 1
    function test_RefundRule1() public make5Activate {
        uint256[5] memory depositAmountsBefore;
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            depositAmountsBefore[i] = s_drbCoordinator.getDepositAmount(s_operatorAddresses[i]);
        }
        requestRandomNumber();
        uint256 requestId = s_consumerExample.lastRequestId();

        // ** increase time
        (uint256 maxWait,,) = s_drbCoordinator.getDurations();
        vm.warp(block.timestamp + maxWait + 1);
        vm.roll(block.number + 1);

        // ** refund
        s_consumerExample.getRefund(requestId);

        // ** assert
        DRBCoordinator.RequestInfo memory requestInfo = s_drbCoordinator.getRequestInfo(requestId); //cost, minDepositForOperator
        uint256 minDepositAtRound = requestInfo.minDepositForOperator;

        uint256[5] memory depositAmountsAfter;
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            depositAmountsAfter[i] = s_drbCoordinator.getDepositAmount(s_operatorAddresses[i]);
            assertEq(depositAmountsBefore[i] - minDepositAtRound, depositAmountsAfter[i]);
        }
        uint256 slashedAmount = minDepositAtRound;
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            uint256 updatedDepositAmount = depositAmountsBefore[i] - slashedAmount;
            assertEq(depositAmountsAfter[i], updatedDepositAmount);
            if (updatedDepositAmount < s_activationThreshold) {
                assertEq(s_drbCoordinator.getActivatedOperatorIndex(s_operatorAddresses[i]), 0);
            } else {
                assertEq(s_drbCoordinator.getActivatedOperatorIndex(s_operatorAddresses[i]), i + 1);
            }
        }

        checkBalanceInvariant();
    }

    /// rule 2
    function test_RefundRule2() public make5Activate {
        uint256[5] memory depositAmountsBefore;
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            depositAmountsBefore[i] = s_drbCoordinator.getDepositAmount(s_operatorAddresses[i]);
        }
        requestRandomNumber();
        uint256 requestId = s_consumerExample.lastRequestId();

        // ** 1 commit
        address operator = s_operatorAddresses[0];
        vm.startPrank(operator);
        uint256 c = 0;
        s_drbCoordinator.commit(requestId, keccak256(abi.encodePacked(c)));
        vm.stopPrank();
        mine();

        // ** increase time
        (, uint256 commitDuration,) = s_drbCoordinator.getDurations();
        vm.warp(block.timestamp + commitDuration + 1);
        vm.roll(block.number + 1);

        // ** balance before
        uint256 balanceBefore = address(s_consumerExample).balance;

        // ** refund
        s_consumerExample.getRefund(requestId);

        // ** balance after
        uint256 balanceAfter = address(s_consumerExample).balance;

        uint256 activatedOperatorsLengthAtRound = s_drbCoordinator.getActivatedOperatorsLengthAtRound(requestId);
        DRBCoordinator.RequestInfo memory requestInfo = s_drbCoordinator.getRequestInfo(requestId); //cost, minDepositForOperator
        uint256 minDepositAtRound = requestInfo.minDepositForOperator;
        uint256 compensateAmount = s_drbCoordinator.getCompensateAmount();
        uint256 L2_GETREFUND_GASUSED = 702530;
        uint256 gasPrice = tx.gasprice;
        uint256 refundTx = gasPrice * L2_GETREFUND_GASUSED;
        uint256 refundAmount = requestInfo.cost + refundTx + compensateAmount;

        assertEq(balanceAfter, balanceBefore + refundAmount, "balanceAfter");

        uint256[5] memory depositAmountsAfter;
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            depositAmountsAfter[i] = s_drbCoordinator.getDepositAmount(s_operatorAddresses[i]);
        }
        uint256 slashedAmount = minDepositAtRound;
        uint256 commitLength = s_drbCoordinator.getCommitsLength(requestId);
        uint256 uncommittedLength = activatedOperatorsLengthAtRound - commitLength;
        uint256 distributedSlashedAmount =
            ((slashedAmount * uncommittedLength) - refundTx - compensateAmount) / commitLength;
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            bool isCommitted = s_drbCoordinator.getCommitOrder(requestId, s_operatorAddresses[i]) > 0;
            if (isCommitted) {
                uint256 updatedDepositAmount = depositAmountsBefore[i] + distributedSlashedAmount;
                assertEq(depositAmountsAfter[i], updatedDepositAmount, "committed operator balance");
                if (updatedDepositAmount < s_activationThreshold) {
                    assertEq(s_drbCoordinator.getActivatedOperatorIndex(s_operatorAddresses[i]), 0);
                } else {
                    assertEq(s_drbCoordinator.getActivatedOperatorIndex(s_operatorAddresses[i]), i + 1);
                }
            } else {
                uint256 updatedDepositAmount = depositAmountsBefore[i] - slashedAmount;
                assertEq(depositAmountsAfter[i], updatedDepositAmount, "uncommitted operator balance");
                if (updatedDepositAmount < s_activationThreshold) {
                    assertEq(s_drbCoordinator.getActivatedOperatorIndex(s_operatorAddresses[i]), 0);
                } else {
                    assertEq(s_drbCoordinator.getActivatedOperatorIndex(s_operatorAddresses[i]), i + 1);
                }
            }
        }

        checkBalanceInvariant();
    }

    /// rule 3
    function test_RefundRule3() public make5Activate {
        uint256[5] memory depositAmountsBefore;
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            depositAmountsBefore[i] = s_drbCoordinator.getDepositAmount(s_operatorAddresses[i]);
        }
        requestRandomNumber();
        uint256 requestId = s_consumerExample.lastRequestId();
        address operator;

        // ** commits
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            operator = s_operatorAddresses[i];
            vm.startPrank(operator);
            s_drbCoordinator.commit(requestId, keccak256(abi.encodePacked(i)));
            vm.stopPrank();
        }
        mine();

        // ** 1 reveal
        operator = s_operatorAddresses[0];
        vm.startPrank(operator);
        s_drbCoordinator.reveal(requestId, bytes32(0));
        vm.stopPrank();

        // ** increase time
        (,, uint256 revealDuration) = s_drbCoordinator.getDurations();
        vm.warp(block.timestamp + revealDuration + 1);
        vm.roll(block.number + 1);

        // ** balance before
        uint256 balanceBefore = address(s_consumerExample).balance;

        // ** refund
        s_consumerExample.getRefund(requestId);

        // ** balance after
        uint256 balanceAfter = address(s_consumerExample).balance;

        DRBCoordinator.RequestInfo memory requestInfo = s_drbCoordinator.getRequestInfo(requestId); //cost, minDepositForOperator
        uint256 minDepositAtRound = requestInfo.minDepositForOperator;
        uint256 compensateAmount = s_drbCoordinator.getCompensateAmount();
        uint256 L2_GETREFUND_GASUSED = 702530;
        uint256 gasPrice = tx.gasprice;
        uint256 refundTx = gasPrice * L2_GETREFUND_GASUSED;
        uint256 refundAmount = requestInfo.cost + refundTx + compensateAmount;

        assertEq(balanceAfter, balanceBefore + refundAmount, "balanceAfter");

        uint256[5] memory depositAmountsAfter;
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            depositAmountsAfter[i] = s_drbCoordinator.getDepositAmount(s_operatorAddresses[i]);
        }
        uint256 slashedAmount = minDepositAtRound;
        uint256 revealLength = s_drbCoordinator.getRevealsLength(requestId);
        uint256 unrevealedLength = s_drbCoordinator.getCommitsLength(requestId) - revealLength;
        uint256 distributedSlashedAmount =
            ((slashedAmount * unrevealedLength) - refundTx - compensateAmount) / revealLength;
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            bool isRevealed = s_drbCoordinator.getRevealOrder(requestId, s_operatorAddresses[i]) > 0;
            if (isRevealed) {
                uint256 updatedDepositAmount = depositAmountsBefore[i] + distributedSlashedAmount;
                assertEq(depositAmountsAfter[i], updatedDepositAmount, "revealed operator balance");
                if (updatedDepositAmount < s_activationThreshold) {
                    assertEq(s_drbCoordinator.getActivatedOperatorIndex(s_operatorAddresses[i]), 0);
                } else {
                    assertEq(s_drbCoordinator.getActivatedOperatorIndex(s_operatorAddresses[i]), i + 1);
                }
            } else {
                uint256 updatedDepositAmount = depositAmountsBefore[i] - slashedAmount;
                assertEq(depositAmountsAfter[i], updatedDepositAmount, "unrevealed operator balance");
                if (updatedDepositAmount < s_activationThreshold) {
                    assertEq(s_drbCoordinator.getActivatedOperatorIndex(s_operatorAddresses[i]), 0);
                } else {
                    assertEq(s_drbCoordinator.getActivatedOperatorIndex(s_operatorAddresses[i]), i + 1);
                }
            }
        }

        checkBalanceInvariant();
    }
}
