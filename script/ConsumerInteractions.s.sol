// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Script, console2} from "forge-std/Script.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {DRBCoordinator} from "../src/DRBCoordinator.sol";
import {RareTitle} from "../src/DRBRareTitle.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Utils} from "./Interactions.s.sol";
import {MockTON} from "../test/shared/MockTON.sol";

contract GetRefund is Utils {
    function run(uint256 requestId) public {
        RareTitle rareTitle = RareTitle(
            payable(
                DevOpsTools.get_most_recent_deployment(
                    "RareTitle",
                    block.chainid
                )
            )
        );
        uint256 deployer = anvilDefaultPrivateKeys[0];
        vm.startBroadcast(deployer);
        rareTitle.getRefund(requestId);
        vm.stopBroadcast();
        console2.log("Refunded request");
    }
}

contract UpdateGameExpiry is Utils {
    function run(uint256 timeleft) public {
        RareTitle rareTitle = RareTitle(
            payable(
                DevOpsTools.get_most_recent_deployment(
                    "RareTitle",
                    block.chainid
                )
            )
        );
        uint256 deployer = anvilDefaultPrivateKeys[0];
        vm.startBroadcast(deployer);
        rareTitle.updateGameExpiry(block.timestamp + timeleft);
        vm.stopBroadcast();
        console2.log("Updated game expiry");
    }
}

contract BlackList is Utils {
    function run() public {
        RareTitle rareTitle = RareTitle(
            payable(
                DevOpsTools.get_most_recent_deployment(
                    "RareTitle",
                    block.chainid
                )
            )
        );
        address[] memory blackList = new address[](1);
        blackList[0] = address(0x8Ec6e633f79F038E352D794D02Ee053fB3895F94);
        vm.startBroadcast();
        rareTitle.blackList(blackList);
        vm.stopBroadcast();
    }
}

contract MintandClaim is Utils {
    function run() public {
        RareTitle rareTitle = RareTitle(
            payable(
                DevOpsTools.get_most_recent_deployment(
                    "RareTitle",
                    block.chainid
                )
            )
        );
        // RareTitle rareTitle = RareTitle(
        //     payable(address(0x5FC8d32690cc91D4c39d9d3abcBD16989F875707))
        // );
        IERC20 tonToken = rareTitle.tonToken();
        console2.log("tonToken", address(tonToken));
        uint256 deployer = anvilDefaultPrivateKeys[0];
        vm.startBroadcast(deployer);
        MockTON(address(tonToken)).mint(address(rareTitle), 1000 ether);
        rareTitle.claimPrize();
        vm.stopBroadcast();
    }
}

contract GetWinnerInfo is Utils {
    function run() public view {
        RareTitle rareTitle = RareTitle(
            payable(
                DevOpsTools.get_most_recent_deployment(
                    "RareTitle",
                    block.chainid
                )
            )
        );
        (
            int24[] memory winnerPoint,
            uint256[] memory winnerLength,
            uint256[] memory prizeAmounts,
            address[][] memory winners
        ) = rareTitle.getWinnersInfo();
        for (uint256 i; i < winnerPoint.length; i++) {
            console2.log("winnerPoint", winnerPoint[i]);
            console2.log("winnerLength", winnerLength[i]);
            console2.log("prizeAmounts", prizeAmounts[i]);
            for (uint256 j; j < winners[i].length; j++) {
                console2.log("winners", winners[i][j]);
            }
        }
    }
}

contract ClaimPrize is Utils {
    function run() public {
        RareTitle rareTitle = RareTitle(
            payable(address(0xCB01f0f7fC79Ef34e480a6a008C2895bd5a6AF7F))
        );

        (int24[] memory winnerPoint, , , address[][] memory winners) = rareTitle
            .getWinnersInfo();
        IERC20 tonToken = rareTitle.tonToken();
        uint256[] memory balanceBefore = new uint256[](winners.length + 1);
        for (uint256 i; i < winnerPoint.length; i++) {
            for (uint256 j; j < winners[i].length; j++) {
                balanceBefore[j] = tonToken.balanceOf(winners[i][j]);
            }
        }
        vm.startBroadcast();
        rareTitle.claimPrize();
        vm.stopBroadcast();
        uint256[] memory balanceAfter = new uint256[](winners.length + 1);
        for (uint256 i; i < winnerPoint.length; i++) {
            for (uint256 j; j < winners[i].length; j++) {
                balanceAfter[j] = tonToken.balanceOf(winners[i][j]);
            }
        }
        for (uint256 i; i < winnerPoint.length; i++) {
            for (uint256 j; j < winners[i].length; j++) {
                console2.log("balanceBefore", balanceBefore[j]);
                console2.log("balanceAfter", balanceAfter[j]);
            }
        }
        console2.log("Claimed prize");
    }
}

contract Request is Utils {
    function run() public {
        RareTitle rareTitle = RareTitle(
            payable(
                DevOpsTools.get_most_recent_deployment(
                    "RareTitle",
                    block.chainid
                )
            )
        );
        (DRBCoordinator drbCoordinator, ) = getContracts();
        uint256 callbackGasLimit = rareTitle.CALLBACK_GAS_LIMIT();
        uint256 cost = drbCoordinator.estimateRequestPrice(
            callbackGasLimit,
            tx.gasprice
        );
        for (uint256 i = 0; i < 5; i++) {
            vm.startBroadcast();
            rareTitle.play{value: cost}();
            vm.stopBroadcast();
            console2.log("Requested title");
        }
    }
}
