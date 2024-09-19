// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DRBCoordinator} from "../../src/DRBCoordinator.sol";
import {DRBCoordinatorStorageTest} from "test/shared/DRBCoordinatorStorageTest.t.sol";
import {MockTON} from "test/shared/MockTON.sol";
import {RareTitle, Ownable} from "../../src/DRBRareTitle.sol";
import {console} from "lib/forge-std/src/console.sol";

contract DRBRareTitleTest is DRBCoordinatorStorageTest {
    RareTitle public s_drbRareTitle;
    MockTON public ton;
    uint256 public constant tonReward = 1e22;
    int8[] private gameBoard;

    function setUp() public override {
        _setUp();
        ton = new MockTON("TON Token", "TON");
        ton.mint(OWNER, 1e24);
        s_drbRareTitle = new RareTitle(
            address(s_drbCoordinator),
            block.timestamp + 100,
            ton,
            tonReward
        );

        ton.transfer(address(s_drbRareTitle), tonReward);
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

    function _play(address player, uint256 cost) internal returns (uint256 requestId, uint256 randomNumber) {
        // request random no while playing
        vm.startPrank(player);
        s_drbRareTitle.play{value: cost}();

        // commit for the requested random no
        requestId = s_drbRareTitle.getLastRequestId();

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
        randomNumber = uint256(keccak256(abi.encodePacked(reveals)));
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
        _depositAndActivateAll();
        uint256 maxTurns = s_drbRareTitle.MAX_NO_OF_TURNS();
        uint256 callbackGasLimit = s_drbRareTitle.CALLBACK_GAS_LIMIT();
        uint256 cost = s_drbCoordinator.estimateRequestPrice(
            callbackGasLimit,
            tx.gasprice
        );
        address player = s_consumerAddresses[0];
        uint256 playedTurns;
        (,uint256 randomNumber) = _play(player, cost);
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
        _depositAndActivateAll();
        uint256 maxTurns = s_drbRareTitle.MAX_NO_OF_TURNS();
        uint256 callbackGasLimit = s_drbRareTitle.CALLBACK_GAS_LIMIT();
        uint256 cost = s_drbCoordinator.estimateRequestPrice(
            callbackGasLimit,
            tx.gasprice
        );

        for (uint256 i; i < s_consumerAddresses.length; ++i) {
            address player = s_consumerAddresses[i];
            uint256 playedTurns;
            (, uint256 randomNumber) = _play(player, cost);
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

    function test_WithdrawTonWhenNotOwner() public {
        vm.startPrank(s_operatorAddresses[0]);
        bytes memory revertData = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_operatorAddresses[0]);
        vm.expectRevert(revertData);
        s_drbRareTitle.withdrawTon();
        vm.stopPrank();
    }

    function test_WithdrawEthWhenNotOwner() public {
        vm.startPrank(s_operatorAddresses[0]);

        bytes memory revertData = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_operatorAddresses[0]);
        vm.expectRevert(revertData);

        s_drbRareTitle.withdrawEth();
        vm.stopPrank();
    }

    function test_WithdrawTonWhenOwner() public {
        uint256 ownerBalanceBefore = ton.balanceOf(OWNER);
        uint256 contractTonBalanceBefore = ton.balanceOf(address(s_drbRareTitle));

        s_drbRareTitle.withdrawTon();

        uint256 ownerBalanceAfter = ton.balanceOf(OWNER);
        uint256 contractTonBalanceAfter = ton.balanceOf(address(s_drbRareTitle));

        assertTrue(ownerBalanceBefore + tonReward == ownerBalanceAfter, "Owner balance after withdrawing TON is not correct");
        assertTrue(contractTonBalanceAfter + tonReward == contractTonBalanceBefore, "Contract balance after withdrawing TON is not correct");
        assertEq(contractTonBalanceAfter, 0);
    }

        function test_WithdrawEthWhenOwner() public {
        uint256 amount = 1 ether;
        payable(address(s_drbRareTitle)).transfer(amount);
        uint256 ownerBalanceBefore = OWNER.balance;
        uint256 contractTonBalanceBefore = address(s_drbRareTitle).balance;

        s_drbRareTitle.withdrawEth();

        uint256 ownerBalanceAfter = OWNER.balance;
        uint256 contractTonBalanceAfter = address(s_drbRareTitle).balance;

        assertTrue(ownerBalanceBefore + amount == ownerBalanceAfter, "Owner balance after withdrawing Eth is not correct");
        assertTrue(contractTonBalanceAfter + amount == contractTonBalanceBefore, "Contract balance after withdrawing Eth is not correct");
        assertEq(contractTonBalanceAfter, 0);
    }

    function test_UpdateGameExpiryWhenInvalidExpiry() public {
        uint256 newExpiry = 0;

        bytes memory revertData = abi.encodeWithSelector(RareTitle.InvalidGameExpiry.selector, newExpiry);
        vm.expectRevert(revertData);

        s_drbRareTitle.updateGameExpiry(newExpiry);
    }

    function test_UpdateGameExpiryWhenNotOwner() public {
        vm.startPrank(s_operatorAddresses[0]);

        bytes memory revertData = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, s_operatorAddresses[0]);
        vm.expectRevert(revertData);

        uint256 newExpiry = block.timestamp + 1000;
        s_drbRareTitle.updateGameExpiry(newExpiry);
        vm.stopPrank();    
    }

    function test_UpdateGameExpiryWhenOwner() public {
        uint256 newExpiry = block.timestamp + 1000;
        s_drbRareTitle.updateGameExpiry(newExpiry);
        uint256 actualExpiry = s_drbRareTitle.gameExpiry();

        assertTrue(newExpiry == actualExpiry, "Actual game expiry does not match the expected value");
    }

    function test_lastRequestIdAfterUserPlay() public {
        _depositAndActivateAll();
        uint256 callbackGasLimit = s_drbRareTitle.CALLBACK_GAS_LIMIT();
        uint256 cost = s_drbCoordinator.estimateRequestPrice(
            callbackGasLimit,
            tx.gasprice
        );
        uint256 expectedLastRequestId;

        for (uint256 i; i < s_consumerAddresses.length; ++i) {
            address player = s_consumerAddresses[i];
            (expectedLastRequestId, ) = _play(player, cost);
            vm.stopPrank();
        }

        uint256 actualLastRequestId = s_drbRareTitle.getLastRequestId();

        assertTrue(actualLastRequestId == expectedLastRequestId, "Actual lastRequestId is not equal to expected value");
    }

    function test_RemainingTurnsForPlayer() public {
        _depositAndActivateAll();
        uint256 callbackGasLimit = s_drbRareTitle.CALLBACK_GAS_LIMIT();
        uint256 cost = s_drbCoordinator.estimateRequestPrice(
            callbackGasLimit,
            tx.gasprice
        );
        address player = s_consumerAddresses[0];

        for (uint256 i; i < s_drbRareTitle.MAX_NO_OF_TURNS(); ++i) {
            _play(player, cost);
        }

        uint256 expectedRemainingTurns = 0;
        vm.startPrank(player);
        uint256 actualRemainingTurns = s_drbRareTitle.viewRemainingTurns();
        vm.stopPrank();

        assertTrue(expectedRemainingTurns == actualRemainingTurns, "Actual remaining turns does not match the expected value");
    }

    function test_PlayerTotalPoints() public {
        _depositAndActivateAll();
        uint256 callbackGasLimit = s_drbRareTitle.CALLBACK_GAS_LIMIT();
        uint256 cost = s_drbCoordinator.estimateRequestPrice(
            callbackGasLimit,
            tx.gasprice
        );
        address player = s_consumerAddresses[0];
        int16 expectedTotalPoints;

        for (uint256 i; i < s_drbRareTitle.MAX_NO_OF_TURNS(); ++i) {
          (, uint256 randomNumber) = _play(player, cost);
          uint256 titleIndex = randomNumber % s_drbRareTitle.BOARD_SIZE();
          expectedTotalPoints += gameBoard[titleIndex];
        }

        vm.startPrank(player);
        int16 actualPlayerPoints = s_drbRareTitle.viewTotalPoints();
        vm.stopPrank();

        assertTrue(actualPlayerPoints == expectedTotalPoints, "Player total points does not match the expected value");
    }

    function test_RevealWinnerBeforeExpiry() public {
        _depositAndActivateAll();
        uint256 callbackGasLimit = s_drbRareTitle.CALLBACK_GAS_LIMIT();
        uint256 cost = s_drbCoordinator.estimateRequestPrice(
            callbackGasLimit,
            tx.gasprice
        );    

        for (uint256 i; i < s_drbRareTitle.MAX_NO_OF_TURNS(); ++i) {
          address player = s_consumerAddresses[i % s_consumerAddresses.length];
          _play(player, cost);
        }

        bytes memory revertData = abi.encodeWithSelector(RareTitle.GameNotExpired.selector);
        vm.expectRevert(revertData);
        s_drbRareTitle.claimPrize();
    }

    function test_ClaimPrizeMultipleTime() public { // WIP
        _depositAndActivateAll();
        uint256 callbackGasLimit = s_drbRareTitle.CALLBACK_GAS_LIMIT();
        uint256 cost = s_drbCoordinator.estimateRequestPrice(
            callbackGasLimit,
            tx.gasprice
        );    

        for (uint256 i; i < s_drbRareTitle.MAX_NO_OF_TURNS(); ++i) {
          address player = s_consumerAddresses[i % s_consumerAddresses.length];
          _play(player, cost);
        }

        _mine(100, 1);
        s_drbRareTitle.claimPrize();

        bytes memory revertData = abi.encodeWithSelector(RareTitle.RewardAlreadyClaimed.selector);
        vm.expectRevert(revertData);
        s_drbRareTitle.claimPrize();
    }
}
