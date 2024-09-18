// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DRBCoordinator} from "../../src/DRBCoordinator.sol";
import {DRBCoordinatorStorageTest} from "test/shared/DRBCoordinatorStorageTest.t.sol";
import {MockTON} from "test/shared/MockTON.sol";
import {RareTitle} from "../../src/DRBRareTitle.sol";
import {console} from "lib/forge-std/src/console.sol";

contract DRBRareTitleTest is DRBCoordinatorStorageTest {
    RareTitle public s_drbRareTitle;
    MockTON public ton;
    uint256 public constant tonReward = 1e22;
    int8[] private gameBoard;

    function setUp() public override {
        _setUp();
        ton = new MockTON("TON Token", "TON");
        s_drbRareTitle = new RareTitle(
            address(s_drbCoordinator),
            block.timestamp + 100,
            ton,
            tonReward
        );

        _depositAndActivateAll();
        _fillGameBoard();
    }

    function _mine(uint256 increaseTimeBy, uint256 increaseBlockBy) internal {
        vm.warp(block.timestamp + increaseTimeBy);
        vm.roll(block.number + increaseBlockBy);
    }

    function _depositAndActivate(address operator) internal {
        vm.startPrank(operator);
        s_drbCoordinator.depositAndActivate{value: s_activationThreshold}();
        address[] memory activatedOperators = s_drbCoordinator
            .getActivatedOperators();
        assertTrue(
            activatedOperators[
                s_drbCoordinator.getActivatedOperatorIndex(operator)
            ] == operator,
            "Activated operator address donot match the passed operator"
        );
        assertTrue(
            s_drbCoordinator.getDepositAmount(operator) ==
                s_activationThreshold,
            "Deposited amount is not equal to activation threshold"
        );
        vm.stopPrank();
    }

    function _depositAndActivateAll() internal {
        vm.stopPrank();
        for (uint256 i = 0; i < s_operatorAddresses.length; ++i) {
            _depositAndActivate(s_operatorAddresses[i]);
        }
        vm.startPrank(OWNER);
    }

    function _play(address player, uint256 cost) internal returns (uint256) {
        // request random no while playing
        vm.startPrank(player);
        s_drbRareTitle.play{value: cost}();

        // commit for the requested random no
        uint256 requestId = s_drbRareTitle.getLastRequestId();

        for (uint256 i; i < s_operatorAddresses.length; ++i) {
            address operator = s_operatorAddresses[i];
            vm.startPrank(operator);
            bytes32 operatorSecret = bytes32(abi.encodePacked(i, player));
            s_drbCoordinator.commit(
                requestId,
                keccak256(abi.encodePacked(operatorSecret))
            );
            vm.stopPrank();
            uint256 gasUsed = vm.lastCallGas().gasTotalUsed;
            console.log("commit GasUsed", gasUsed);
            _mine(1, 1);

            uint256 commitOrder = s_drbCoordinator.getCommitOrder(
                requestId,
                operator
            );
            assertEq(commitOrder, i + 1);
        }
        DRBCoordinator.RoundInfo memory roundInfo = s_drbCoordinator
            .getRoundInfo(requestId);
        bytes32[] memory commits = s_drbCoordinator.getCommits(requestId);
        assertEq(commits.length, 5);
        assertEq(roundInfo.randomNumber, 0);
        assertEq(roundInfo.fulfillSucceeded, false);

        // reveal for the requested random no
        bytes32[] memory reveals = new bytes32[](s_operatorAddresses.length);
        for (uint256 i; i < s_operatorAddresses.length; ++i) {
            address operator = s_operatorAddresses[i];
            vm.startPrank(operator);
            bytes32 secret = bytes32(abi.encodePacked(i, player));
            s_drbCoordinator.reveal(requestId, secret);
            reveals[i] = secret;
            vm.stopPrank();

            uint256 revealOrder = s_drbCoordinator.getRevealOrder(
                requestId,
                operator
            );
            assertEq(revealOrder, i + 1);
        }
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(reveals)));
        bytes32[] memory revealsOnChain = s_drbCoordinator.getReveals(
            requestId
        );
        assertEq(revealsOnChain.length, 5);
        roundInfo = s_drbCoordinator.getRoundInfo(requestId);
        assertEq(roundInfo.randomNumber, randomNumber);
        assertEq(roundInfo.fulfillSucceeded, true);

        for (uint256 i; i < s_operatorAddresses.length; i++) {
            uint256 depositAmount = s_drbCoordinator.getDepositAmount(
                s_operatorAddresses[i]
            );
            if (depositAmount < s_activationThreshold) {
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
        return randomNumber;
    }

    function _fillGameBoard() internal {
        uint256 i;
        gameBoard.push(100);
        ++i;
        uint256 count = 3;
        do {
            gameBoard.push(30);
            ++i;
            --count;
        } while (count > 0);

        count = 10;
        do {
            gameBoard.push(20);
            ++i;
            --count;
        } while (count > 0);

        count = 40;
        do {
            gameBoard.push(10);
            ++i;
            --count;
        } while (count > 0);

        count = 46;
        do {
            gameBoard.push(-5);
            ++i;
            --count;
        } while (count > 0);
    }

    function test_PlayOnceSingleUser() public {
        uint256 maxTurns = s_drbRareTitle.MAX_NO_OF_TURNS();
        uint256 callbackGasLimit = s_drbRareTitle.CALLBACK_GAS_LIMIT();
        uint256 cost = s_drbCoordinator.estimateRequestPrice(
            callbackGasLimit,
            tx.gasprice
        );
        address player = s_consumerAddresses[0];
        uint256 playedTurns;
        uint256 randomNumber = _play(player, cost);
        ++playedTurns;
        uint256 gameIndex = randomNumber % s_drbRareTitle.BOARD_SIZE();
        int16 expectedPoints = gameBoard[gameIndex];
        vm.startPrank(player);
        int16 actualPoints = s_drbRareTitle.viewTotalPoints();
        uint256 actualRemainingTurns = s_drbRareTitle.viewRemainingTurns();
        vm.stopPrank();
        assertTrue(
            actualPoints == expectedPoints,
            "Actual Player points are not equal to expected value"
        );
        assertTrue(
            maxTurns - playedTurns == actualRemainingTurns,
            "Actual remaining turns does not match expected remaining turns"
        );
    }

    function test_PlayOnce5Users() public {
        uint256 maxTurns = s_drbRareTitle.MAX_NO_OF_TURNS();
        uint256 callbackGasLimit = s_drbRareTitle.CALLBACK_GAS_LIMIT();
        uint256 cost = s_drbCoordinator.estimateRequestPrice(
            callbackGasLimit,
            tx.gasprice
        );
        for (uint256 i; i < s_consumerAddresses.length; ++i) {
            address player = s_consumerAddresses[i];
            uint256 playedTurns;
            uint256 randomNumber = _play(player, cost);
            ++playedTurns;
            uint256 gameIndex = randomNumber % s_drbRareTitle.BOARD_SIZE();
            int16 expectedPoints = gameBoard[gameIndex];
            vm.startPrank(player);
            int16 actualPoints = s_drbRareTitle.viewTotalPoints();
            uint256 actualRemainingTurns = s_drbRareTitle.viewRemainingTurns();
            vm.stopPrank();
            assertTrue(
                actualPoints == expectedPoints,
                "Actual Player points are not equal to expected value"
            );
            assertTrue(
                maxTurns - playedTurns == actualRemainingTurns,
                "Actual remaining turns does not match expected remaining turns"
            );
        }
    }
}
