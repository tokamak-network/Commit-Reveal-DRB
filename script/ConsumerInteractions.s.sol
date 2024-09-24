// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Script, console2} from "forge-std/Script.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {DRBCoordinator} from "../src/DRBCoordinator.sol";
import {RareTitle} from "../src/DRBRareTitle.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Utils} from "./Interactions.s.sol";

contract ClaimPrize is Utils {
    function run() public {
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
        rareTitle.claimPrize();
        vm.stopBroadcast();
        console2.log("Claimed prize");
    }
}

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
