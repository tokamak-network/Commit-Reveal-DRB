// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {Commit2Reveal2DRB} from "../src/Commit2Reveal2DRB.sol";
import {console2} from "forge-std/Test.sol";
import {NetworkHelperConfig} from "./NetworkHelperConfig.s.sol";

contract DeployCommit2Reveal2 is Script {
    uint256 s_maxActivatedOperators = 10;
    string public name = "Tokamak DRB";
    string public version = "1";
    bytes32 public nameHash = keccak256(bytes(name));
    bytes32 public versionHash = keccak256(bytes(version));

    function deployCommit2RevealUsingConfig()
        public
        returns (Commit2Reveal2DRB commit2Reveal2)
    {
        NetworkHelperConfig networkHelperConfig = new NetworkHelperConfig();
        (
            uint256 activationThreshold,
            ,
            uint256 flatFee,
            uint256 l1GasCostMode,
            ,
            ,

        ) = networkHelperConfig.activeNetworkConfig();
        console2.log("activationThreshold:", activationThreshold);
        commit2Reveal2 = deployCommit2Reveal(
            activationThreshold,
            flatFee,
            l1GasCostMode
        );
    }

    function deployCommit2Reveal(
        uint256 activationThreshold,
        uint256 flatFee,
        uint256 l1GasCostMode
    ) public returns (Commit2Reveal2DRB commit2Reveal2) {
        vm.startBroadcast();
        commit2Reveal2 = new Commit2Reveal2DRB(
            activationThreshold,
            flatFee,
            s_maxActivatedOperators,
            name,
            version
        );
        vm.stopBroadcast();
        (uint8 mode, ) = commit2Reveal2.getL1FeeCalculationMode();
        if (uint256(mode) != l1GasCostMode) {
            vm.startBroadcast();
            commit2Reveal2.setL1FeeCalculation(uint8(l1GasCostMode), 100);
            vm.stopBroadcast();
            console2.log("Set L1 fee calculation mode to:", l1GasCostMode);
        }
    }

    function run() public returns (Commit2Reveal2DRB commit2Reveal2) {
        commit2Reveal2 = deployCommit2RevealUsingConfig();
        console2.log("Deployed Commit2Reveal at:", address(commit2Reveal2));
    }
}
