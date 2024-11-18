// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {Script, console2} from "forge-std/Script.sol";
import {ConsumerExample} from "../src/ConsumerExample.sol";

contract DeployConsumerExample is Script {
    error DRBCoordinatorNotDeployed();

    function run() public {
        address commit2reveal2 = DevOpsTools.get_most_recent_deployment(
            "Commit2Reveal2DRB",
            block.chainid
        );
        vm.startBroadcast();
        ConsumerExample consumer = new ConsumerExample(commit2reveal2);
        vm.stopBroadcast();
        console2.log("Deployed ConsumerExample at:", address(consumer));
    }
}
