// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DRBCoordinator} from "../../src/DRBCoordinator.sol";
import {DRBCoordinatorStorageTest} from "test/shared/DRBCoordinatorStorageTest.t.sol";
import {ConsumerExample} from "../../src/ConsumerExample.sol";
import {console2} from "forge-std/Test.sol";
import {RareTitle} from "../../src/DRBRareTitle.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MockTON} from "../shared/MockTON.sol";

contract RareTitleTest is DRBCoordinatorStorageTest {
    uint256 s_operatorAddressesLength = 3;
    modifier make3Activate() {
        vm.stopPrank();
        for (uint256 i = 0; i < s_operatorAddressesLength; i++) {
            address operator = s_operatorAddresses[i];
            vm.startPrank(operator);
            s_drbCoordinator.depositAndActivate{
                value: s_activationThreshold * 2000
            }();
            vm.stopPrank();
        }
        vm.startPrank(OWNER);
        _;
    }

    function setUp() public override {
        _setUp();
    }

    function reqeustRandomNumber() public {
        uint256 callbackGasLimit = s_rareTitle.CALLBACK_GAS_LIMIT();
        uint256 cost = s_drbCoordinator.estimateRequestPrice(
            callbackGasLimit,
            tx.gasprice
        );
        s_rareTitle.play{value: cost}();
    }

    function checkBalanceInvariant() public view {
        uint256 balanceOfDRBCoordinator = address(s_drbCoordinator).balance;
        uint256 depositSum;
        for (uint256 i; i < s_operatorAddressesLength; i++) {
            depositSum += s_drbCoordinator.getDepositAmount(
                s_operatorAddresses[i]
            );
        }
        assertEq(
            balanceOfDRBCoordinator / 10,
            depositSum / 10,
            "balanceOfDRBCoordinator invariant assertion"
        );
    }

    function test_RareTitleRefundRule1() public make3Activate {
        uint256[3] memory depositAmountsBefore;
        for (uint256 i; i < s_operatorAddressesLength; i++) {
            depositAmountsBefore[i] = s_drbCoordinator.getDepositAmount(
                s_operatorAddresses[i]
            );
        }
        reqeustRandomNumber();
        uint256 requestId = 0;

        // ** increase time
        (uint256 maxWait, , ) = s_drbCoordinator.getDurations();
        vm.warp(block.timestamp + maxWait + 1);
        vm.roll(block.number + 1);

        // ** refund
        s_rareTitle.getRefund(requestId);

        DRBCoordinator.RequestInfo memory requestInfo = s_drbCoordinator
            .getRequestInfo(requestId); //cost, minDepositForOperator
        uint256 minDepositAtRound = requestInfo.minDepositForOperator;

        uint256[5] memory depositAmountsAfter;
        for (uint256 i; i < s_operatorAddressesLength; i++) {
            depositAmountsAfter[i] = s_drbCoordinator.getDepositAmount(
                s_operatorAddresses[i]
            );
            assertEq(
                depositAmountsBefore[i] - minDepositAtRound,
                depositAmountsAfter[i]
            );
        }
        uint256 slashedAmount = minDepositAtRound;
        for (uint256 i; i < s_operatorAddressesLength; i++) {
            uint256 updatedDepositAmount = depositAmountsBefore[i] -
                slashedAmount;
            assertEq(depositAmountsAfter[i], updatedDepositAmount);
            if (updatedDepositAmount < s_activationThreshold) {
                assertEq(
                    s_drbCoordinator.getActivatedOperatorIndex(
                        s_operatorAddresses[i]
                    ),
                    0
                );
            } else {
                assertEq(
                    s_drbCoordinator.getActivatedOperatorIndex(
                        s_operatorAddresses[i]
                    ),
                    i + 1
                );
            }
        }

        checkBalanceInvariant();
    }

    function mine() public {
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
    }

    function test_RareTitleRefundRule2() public make3Activate {
        uint256[3] memory depositAmountsBefore;
        for (uint256 i; i < s_operatorAddressesLength; i++) {
            depositAmountsBefore[i] = s_drbCoordinator.getDepositAmount(
                s_operatorAddresses[i]
            );
        }
        reqeustRandomNumber();

        uint256 requestId = 0;

        // ** 1 commit
        address operator = s_operatorAddresses[0];
        vm.startPrank(operator);
        uint256 c = 0;
        s_drbCoordinator.commit(requestId, keccak256(abi.encodePacked(c)));
        vm.stopPrank();
        mine();

        // ** increase time
        (, uint256 commitDuration, ) = s_drbCoordinator.getDurations();
        vm.warp(block.timestamp + commitDuration + 1);
        vm.roll(block.number + 1);

        // ** balance before
        uint256 balanceBefore = address(OWNER).balance;

        // ** refund
        s_rareTitle.getRefund(requestId);

        // ** balance after
        uint256 balanceAfter = address(OWNER).balance;

        uint256 activatedOperatorsLengthAtRound = s_drbCoordinator
            .getActivatedOperatorsLengthAtRound(requestId);
        DRBCoordinator.RequestInfo memory requestInfo = s_drbCoordinator
            .getRequestInfo(requestId); //cost, minDepositForOperator
        uint256 minDepositAtRound = requestInfo.minDepositForOperator;
        uint256 compensateAmount = s_drbCoordinator.getCompensateAmount();
        uint256 refundAmount = requestInfo.cost +
            requestInfo.requestAndRefundCost +
            s_compensateAmount;

        assertEq(balanceAfter, balanceBefore + refundAmount, "balanceAfter");

        uint256[5] memory depositAmountsAfter;
        for (uint256 i; i < s_operatorAddressesLength; i++) {
            depositAmountsAfter[i] = s_drbCoordinator.getDepositAmount(
                s_operatorAddresses[i]
            );
        }
        uint256 slashedAmount = minDepositAtRound;
        uint256 commitLength = s_drbCoordinator.getCommitsLength(requestId);
        uint256 uncommittedLength = activatedOperatorsLengthAtRound -
            commitLength;
        uint256 distributedSlashedAmount = ((slashedAmount *
            uncommittedLength) -
            requestInfo.requestAndRefundCost -
            compensateAmount) / commitLength;
        for (uint256 i; i < s_operatorAddressesLength; i++) {
            bool isCommitted = s_drbCoordinator.getCommitOrder(
                requestId,
                s_operatorAddresses[i]
            ) > 0;
            if (isCommitted) {
                uint256 updatedDepositAmount = depositAmountsBefore[i] +
                    distributedSlashedAmount;
                assertEq(
                    depositAmountsAfter[i],
                    updatedDepositAmount,
                    "committed operator balance"
                );
                if (updatedDepositAmount < s_activationThreshold) {
                    assertEq(
                        s_drbCoordinator.getActivatedOperatorIndex(
                            s_operatorAddresses[i]
                        ),
                        0
                    );
                } else {
                    assertEq(
                        s_drbCoordinator.getActivatedOperatorIndex(
                            s_operatorAddresses[i]
                        ),
                        i + 1
                    );
                }
            } else {
                uint256 updatedDepositAmount = depositAmountsBefore[i] -
                    slashedAmount;
                assertEq(
                    depositAmountsAfter[i],
                    updatedDepositAmount,
                    "uncommitted operator balance"
                );
                if (updatedDepositAmount < s_activationThreshold) {
                    assertEq(
                        s_drbCoordinator.getActivatedOperatorIndex(
                            s_operatorAddresses[i]
                        ),
                        0
                    );
                } else {
                    assertEq(
                        s_drbCoordinator.getActivatedOperatorIndex(
                            s_operatorAddresses[i]
                        ),
                        i + 1
                    );
                }
            }
        }

        checkBalanceInvariant();
    }

    function test_RareTitleRefundRule3() public make3Activate {
        uint256[3] memory depositAmountsBefore;
        for (uint256 i; i < s_operatorAddressesLength; i++) {
            depositAmountsBefore[i] = s_drbCoordinator.getDepositAmount(
                s_operatorAddresses[i]
            );
        }
        reqeustRandomNumber();
        uint256 requestId = 0;
        address operator;

        // ** commits
        for (uint256 i; i < s_operatorAddressesLength; i++) {
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
        (, , uint256 revealDuration) = s_drbCoordinator.getDurations();
        vm.warp(block.timestamp + revealDuration + 1);
        vm.roll(block.number + 1);

        // ** balance before
        uint256 balanceBefore = address(OWNER).balance;

        // ** refund
        s_rareTitle.getRefund(requestId);

        // ** balance after
        uint256 balanceAfter = address(OWNER).balance;

        DRBCoordinator.RequestInfo memory requestInfo = s_drbCoordinator
            .getRequestInfo(requestId); //cost, minDepositForOperator
        uint256 minDepositAtRound = requestInfo.minDepositForOperator;
        uint256 compensateAmount = s_drbCoordinator.getCompensateAmount();
        uint256 refundAmount = requestInfo.cost +
            requestInfo.requestAndRefundCost +
            s_compensateAmount;

        assertEq(balanceAfter, balanceBefore + refundAmount, "balanceAfter");

        uint256[5] memory depositAmountsAfter;
        for (uint256 i; i < s_operatorAddressesLength; i++) {
            depositAmountsAfter[i] = s_drbCoordinator.getDepositAmount(
                s_operatorAddresses[i]
            );
        }
        uint256 slashedAmount = minDepositAtRound;
        uint256 revealLength = s_drbCoordinator.getRevealsLength(requestId);
        uint256 unrevealedLength = s_drbCoordinator.getCommitsLength(
            requestId
        ) - revealLength;
        uint256 distributedSlashedAmount = ((slashedAmount * unrevealedLength) -
            requestInfo.requestAndRefundCost -
            compensateAmount) / revealLength;
        for (uint256 i; i < s_operatorAddressesLength; i++) {
            bool isRevealed = s_drbCoordinator.getRevealOrder(
                requestId,
                s_operatorAddresses[i]
            ) > 0;
            if (isRevealed) {
                uint256 updatedDepositAmount = depositAmountsBefore[i] +
                    distributedSlashedAmount;
                assertEq(
                    depositAmountsAfter[i],
                    updatedDepositAmount,
                    "revealed operator balance"
                );
                if (updatedDepositAmount < s_activationThreshold) {
                    assertEq(
                        s_drbCoordinator.getActivatedOperatorIndex(
                            s_operatorAddresses[i]
                        ),
                        0
                    );
                } else {
                    assertEq(
                        s_drbCoordinator.getActivatedOperatorIndex(
                            s_operatorAddresses[i]
                        ),
                        i + 1
                    );
                }
            } else {
                uint256 updatedDepositAmount = depositAmountsBefore[i] -
                    slashedAmount;
                assertEq(
                    depositAmountsAfter[i],
                    updatedDepositAmount,
                    "unrevealed operator balance"
                );
                if (updatedDepositAmount < s_activationThreshold) {
                    assertEq(
                        s_drbCoordinator.getActivatedOperatorIndex(
                            s_operatorAddresses[i]
                        ),
                        0
                    );
                } else {
                    assertEq(
                        s_drbCoordinator.getActivatedOperatorIndex(
                            s_operatorAddresses[i]
                        ),
                        i + 1
                    );
                }
            }
        }

        checkBalanceInvariant();
    }

    function test_gasOfRareTitle() public make3Activate {
        uint256 roundsNum = 1000;
        // request 100 times
        console2.log("requests ----");
        for (uint256 i = 0; i < 100; i++) {
            vm.stopPrank();
            uint256 callbackGasLimit = s_rareTitle.CALLBACK_GAS_LIMIT();
            uint256 cost = s_drbCoordinator.estimateRequestPrice(
                callbackGasLimit,
                tx.gasprice
            );
            vm.startPrank(s_consumerAddresses[i]);
            for (uint256 j = 0; j < 10; j++) {
                s_rareTitle.play{value: cost}();
                uint256 gasUsed = vm.lastCallGas().gasTotalUsed;
                console2.log("gasUsed", i * 10 + j, gasUsed);
            }
            vm.stopPrank();
        }
        console2.log("--------------------");

        // commit 100 rounds
        console2.log("commit 1000 rounds");
        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(s_operatorAddresses[i]);
            for (uint256 j = 0; j < roundsNum; j++) {
                s_drbCoordinator.commit(j, keccak256(abi.encodePacked(j)));
                uint256 gasUsed = vm.lastCallGas().gasTotalUsed;
                console2.log("gasUsed", i * roundsNum + j, gasUsed);
            }
            vm.stopPrank();
        }
        console2.log("--------------------");

        mine();

        // reveal 100 rounds
        console2.log("reveal 1000 rounds");
        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(s_operatorAddresses[i]);
            for (uint256 j = 0; j < roundsNum; j++) {
                s_drbCoordinator.reveal(j, bytes32(j));
                uint256 gasUsed = vm.lastCallGas().gasTotalUsed;
                console2.log("gasUsed", i * roundsNum + j, gasUsed);
                if (i == 2) {
                    (, , RareTitle.RequestStatus status) = s_rareTitle
                        .s_requests(j);
                    assertEq(
                        uint256(status),
                        uint256(RareTitle.RequestStatus.FULFILLED),
                        Strings.toString(j)
                    );
                }
            }
            vm.stopPrank();
        }

        for (uint256 i = 0; i < 100; i++) {
            vm.startPrank(s_consumerAddresses[i]);
            (
                uint256[] memory requestIds,
                uint256[] memory randomNumbers,
                uint8[] memory requestStatus,
                int24 totalPoints,
                uint8 totalTurns,
                int24[] memory _winnerPoint,
                uint256[] memory winnerLength,
                uint256[] memory prizeAmounts,
                uint256 _gameExpiry
            ) = s_rareTitle.viewEventInfos();
            console2.log("totalPoints", totalPoints);
            console2.log("totalTurns", totalTurns);
            //console2.log("_winnerPoint", _winnerPoint);
            //console2.log("winnerLength", winnerLength);
            console2.log("_gameExpiry", _gameExpiry);
            vm.stopPrank();
        }
        uint256 count;
        int24[] memory winnerPoint;
        uint256[] memory winnerLength;
        uint256[] memory prizeAmounts;
        address[][] memory winners;
        for (uint256 test = 0; test < 29; test++) {
            (winnerPoint, winnerLength, prizeAmounts, winners) = s_rareTitle
                .getWinnersInfo();
            //console2.log("winnerPoint", winnerPoint);
            //console2.log("winnerLength", winnerLength);
            // for (uint256 i = 0; i < winners.length; i++) {
            //     console2.log("winner", i, winners[i]);
            // }
            address[] memory blackList = new address[](winners[0].length);
            for (uint256 i = 0; i < winners[0].length; i++) {
                blackList[i] = winners[0][i];
            }
            count += winners[0].length;
            vm.startPrank(OWNER);
            s_rareTitle.blackList(blackList);
            vm.stopPrank();
            for (uint256 i = 0; i < winners[0].length; i++) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        RareTitle.UserTurnsExhausted.selector,
                        winners[0][i]
                    )
                );
                vm.startPrank(winners[0][i]);
                s_rareTitle.play();
                vm.stopPrank();
            }
        }
        console2.log("black listed count", count);

        // ** /////
        for (uint256 i = 100; i < 200; i++) {
            vm.stopPrank();
            uint256 callbackGasLimit = s_rareTitle.CALLBACK_GAS_LIMIT();
            uint256 cost = s_drbCoordinator.estimateRequestPrice(
                callbackGasLimit,
                tx.gasprice
            );
            vm.startPrank(s_consumerAddresses[i]);
            for (uint256 j = 0; j < 10; j++) {
                s_rareTitle.play{value: cost}();
                uint256 gasUsed = vm.lastCallGas().gasTotalUsed;
                console2.log("gasUsed", i * 10 + j, gasUsed);
            }
            vm.stopPrank();
        }
        console2.log("--------------------");

        // commit 100 rounds
        console2.log("commit 1000 rounds");
        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(s_operatorAddresses[i]);
            for (uint256 j = roundsNum; j < roundsNum * 2; j++) {
                s_drbCoordinator.commit(j, keccak256(abi.encodePacked(j)));
                uint256 gasUsed = vm.lastCallGas().gasTotalUsed;
                console2.log("gasUsed", i * roundsNum * 2 + j, gasUsed);
            }
            vm.stopPrank();
        }
        console2.log("--------------------");

        mine();

        // reveal 100 rounds
        console2.log("reveal 1000 rounds");
        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(s_operatorAddresses[i]);
            for (uint256 j = roundsNum; j < roundsNum * 2; j++) {
                s_drbCoordinator.reveal(j, bytes32(j));
                uint256 gasUsed = vm.lastCallGas().gasTotalUsed;
                console2.log("gasUsed", i * roundsNum * 2 + j, gasUsed);
                if (i == 2) {
                    (, , RareTitle.RequestStatus status) = s_rareTitle
                        .s_requests(j);
                    assertEq(
                        uint256(status),
                        uint256(RareTitle.RequestStatus.FULFILLED),
                        Strings.toString(j)
                    );
                }
            }
            vm.stopPrank();
        }

        for (uint256 test = 0; test < 15; test++) {
            (winnerPoint, winnerLength, prizeAmounts, winners) = s_rareTitle
                .getWinnersInfo();
            //console2.log("winnerPoint", winnerPoint);
            //console2.log("winnerLength", winnerLength);
            // for (uint256 i = 0; i < winners.length; i++) {
            //     console2.log("winner", i, winners[i]);
            // }
            address[] memory blackList = new address[](winners[0].length);
            for (uint256 i = 0; i < winners[0].length; i++) {
                blackList[i] = winners[0][i];
            }
            count += winners[0].length;
            vm.startPrank(OWNER);
            s_rareTitle.blackList(blackList);
            vm.stopPrank();
            for (uint256 i = 0; i < winners[0].length; i++) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        RareTitle.UserTurnsExhausted.selector,
                        winners[0][i]
                    )
                );
                vm.startPrank(winners[0][i]);
                s_rareTitle.play();
                vm.stopPrank();
            }
        }
        console2.log("black listed count", count);

        // ** /////#

        vm.warp(block.timestamp + s_gameExpiry + 1);
        mine();
        MockTON(address(s_tonToken)).mint(address(s_rareTitle), s_reward);
        // claim prize
        (winnerPoint, winnerLength, prizeAmounts, winners) = s_rareTitle
            .getWinnersInfo();
        //console2.log("winnerPoint", winnerPoint);
        //console2.log("winnerLength", winnerLength);
        uint256[] memory balancesBefore = new uint256[](winners[0].length);
        for (uint256 i = 0; i < winners[0].length; i++) {
            balancesBefore[i] = s_tonToken.balanceOf(winners[0][i]);
        }
        vm.startPrank(OWNER);
        s_rareTitle.claimPrize();
        vm.stopPrank();
        // for (uint256 i = 0; i < winners.length; i++) {
        //     uint256 balanceAfter = s_tonToken.balanceOf(winners[i]);
        //     assertEq(
        //         balanceAfter,
        //         balancesBefore[i] + s_reward / winners.length,
        //         Strings.toString(i)
        //     );
        // }
    }
}
