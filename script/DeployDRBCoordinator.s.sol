// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {DRBCoordinator} from "../src/DRBCoordinator.sol";

contract DeployDRBCoordinator is Script {
    function run() public {
        uint256 minDeposit = 1 ether;
        uint256[3] memory compensations = [
            uint256(0.2 ether),
            0.3 ether,
            0.4 ether
        ];
        uint256 flatFee = 0.01 ether;
        vm.startBroadcast();
        DRBCoordinator coordinator = new DRBCoordinator(
            minDeposit,
            flatFee,
            compensations
        );
        vm.stopBroadcast();
        console2.log("Deployed DRBCoordinator at:", address(coordinator));
    }
}
