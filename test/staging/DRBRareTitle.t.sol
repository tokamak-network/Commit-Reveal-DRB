// SPDX-License-Identifier: MIT
pragma solidity 0.8.26^;

import {DRBCoordinator} from "../../src/DRBCoordinator.sol";
import { DRBCoordinatorStorageTest } from "test/shared/DRBCoordinatorStorageTest.t.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DRBRareTitle} from "../../src/DRBRareTitle.sol";
import {console2} from "forge-std/Test.sol";

contract DRBRareTitleTest is DRBCoordinatorStorageTest {
    DRBRareTitle public immutable s_drbRareTitle;
    ERC20 public immutable ton;
    uint256 public constant tonReward = 1e22;

    function setUp() public override {
        _setUp();
        ton = new ERC20("TON Token", "TON");
        s_drbRareTitle = new DRBRareTitle(address(s_drbCoordinator), ton, tonReward);
        _depositAndActivateAll();
    }

    function mine() public {
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
    }

    function _depositAndActivate(address operator) internal {
        vm.startPrank(operator);
        s_drbCoordinator.depositAndActivate{value: s_activationThreshold}();
        address[] memory activatedOperators = s_drbCoordinator.getActivatedOperators();
        assertTrue(activatedOperators[s_drbCoordinator.getActivatedOperatorIndex(operator)] == operator),
        "Activated operator address donot match the passed operator"
        assertTrue(
            s_drbCoordinator.getDepositAmount(operator) == s_activationThreshold,
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

    function test_PlaySingleUser() public { // WIP
        address consumer = s_consumerAddresses[0];
        vm.startPrank(consumer);

        uint256 callbackGasLimit = s_drbRareTitle.CALLBACK_GAS_LIMIT();
        uint256 cost = s_drbRareTitle.estimateRequestPrice(
            callbackGasLimit,
            tx.gasprice
        );
        s_consumerExample.requestRandomNumber{value: cost}();
    }
}