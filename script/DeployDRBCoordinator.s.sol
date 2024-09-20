// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {DRBCoordinator} from "../src/DRBCoordinator.sol";
import {NetworkHelperConfig} from "./NetworkHelperConfig.s.sol";

contract DeployDRBCoordinator is Script {
    function deployDRBCoordinatorUsingConfig()
        public
        returns (DRBCoordinator drbCoordinator)
    {
        NetworkHelperConfig networkHelperConfig = new NetworkHelperConfig();
        (
            uint256 activationThreshold,
            uint256 compensateAmount,
            uint256 flatFee,
            uint256 l1GasCostMode
        ) = networkHelperConfig.activeNetworkConfig();
        drbCoordinator = deployDRBCoordinator(
            activationThreshold,
            flatFee,
            compensateAmount,
            l1GasCostMode
        );
    }

    function deployDRBCoordinator(
        uint256 activationThreshold,
        uint256 flatFee,
        uint256 compensateAmount,
        uint256 l1GasCostMode
    ) public returns (DRBCoordinator drbCoordinator) {
        vm.startBroadcast();
        drbCoordinator = new DRBCoordinator(
            activationThreshold,
            flatFee,
            compensateAmount
        );
        vm.stopBroadcast();
        (uint8 mode, ) = drbCoordinator.getL1FeeCalculationMode();
        if (uint256(mode) != l1GasCostMode) {
            vm.startBroadcast();
            drbCoordinator.setL1FeeCalculation(uint8(l1GasCostMode), 100);
            vm.stopBroadcast();
            console2.log("Set L1 fee calculation mode to:", l1GasCostMode);
        }
    }

    function run() public returns (DRBCoordinator drbCoordinator) {
        drbCoordinator = deployDRBCoordinatorUsingConfig();
        console2.log("Deployed DRBCoordinator at:", address(drbCoordinator));
    }
}
