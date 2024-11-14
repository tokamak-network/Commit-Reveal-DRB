// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {RareTitlePrizeDistribution} from "../../src/test/DRBRareTitlePrizeDistribution.sol";
import {MockTON} from "test/shared/MockTON.sol";
import {DRBCoordinatorStorageTest} from "test/shared/DRBCoordinatorStorageTest.t.sol";
import {console2} from "forge-std/Test.sol";

contract DRBRareTitlePrizeDistributionTest is DRBCoordinatorStorageTest {
    uint256 s_operatorAddressesLength = 3;
    RareTitlePrizeDistribution s_drbRareTitlePrizeDistribution;
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
        s_drbRareTitlePrizeDistribution = new RareTitlePrizeDistribution(
            address(s_tonToken)
        );
        MockTON(address(s_tonToken)).mint(
            address(s_drbRareTitlePrizeDistribution),
            1000 ether
        );
    }

    function test_prizeDistribution() public {
        uint256 roundsNum = 1000;
        // fulfill 100 times
        for (uint256 i = 0; i < 100; i++) {
            vm.stopPrank();
            vm.startPrank(s_consumerAddresses[i]);
            s_drbRareTitlePrizeDistribution.fulfillRandomWords(i, i);
            vm.stopPrank();
        }
        console2.log("--------------------");

        (
            int24[] memory winnerPoint,
            uint256[] memory winnerLength,
            uint256[] memory prizeAmounts,
            address[][] memory winners
        ) = s_drbRareTitlePrizeDistribution.getWinnersInfo();

        for (uint256 i = 0; i < winnerPoint.length; i++) {
            if (winnerLength[i] == 0) {
                break;
            }
            console2.log("winnerPoint: ", winnerPoint[i]);
            console2.log("winnerLength: ", winnerLength[i]);
            console2.log("prizeAmounts: ", prizeAmounts[i]);
            for (uint256 j = 0; j < winnerLength[i]; j++) {
                console2.log("winner: ", winners[i][j]);
            }
        }

        console2.log("--------------------");
        console2.log("--------------------");

        s_drbRareTitlePrizeDistribution.blackList(winners[2]);

        (
            winnerPoint,
            winnerLength,
            prizeAmounts,
            winners
        ) = s_drbRareTitlePrizeDistribution.getWinnersInfo();

        s_drbRareTitlePrizeDistribution.claimPrize();

        for (uint256 i = 0; i < winnerPoint.length; i++) {
            if (winnerLength[i] == 0) {
                break;
            }
            console2.log("winnerPoint: ", winnerPoint[i]);
            console2.log("winnerLength: ", winnerLength[i]);
            for (uint256 j = 0; j < winnerLength[i]; j++) {
                console2.log("winner: ", winners[i][j]);
                console2.log("balance: ", s_tonToken.balanceOf(winners[i][j]));
                assertEq(s_tonToken.balanceOf(winners[i][j]), prizeAmounts[i]);
            }
        }
    }
}
