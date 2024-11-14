// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {NetworkHelperConfig} from "./NetworkHelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RareTitle} from "../src/DRBRareTitle.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {MockTON} from "../test/shared/MockTON.sol";

contract DeployRareTitle is Script {
    function deployRareTitleUsingConfig() public returns (RareTitle rareTitle) {
        NetworkHelperConfig networkHelperConfig = new NetworkHelperConfig();
        (
            ,
            ,
            ,
            ,
            uint256 gameExpiry,
            IERC20 tonToken,
            uint256 reward
        ) = networkHelperConfig.activeNetworkConfig();
        address drbCoordinator = DevOpsTools.get_most_recent_deployment(
            "DRBCoordinator",
            block.chainid
        );
        MockTON _tonToken;
        if (tonToken == IERC20(address(0))) {
            vm.startBroadcast();
            _tonToken = new MockTON("TON", "TON");
            _tonToken.mint(address(this), 1000000000000000000000000);
            vm.stopBroadcast();
            tonToken = IERC20(address(_tonToken));
        }
        rareTitle = deployRareTitle(
            gameExpiry,
            tonToken,
            reward,
            drbCoordinator
        );
    }

    function deployRareTitle(
        uint256 gameExpiry,
        IERC20 tonToken,
        uint256 reward,
        address drbCoordinator
    ) public returns (RareTitle rareTitle) {
        vm.startBroadcast();
        rareTitle = new RareTitle(drbCoordinator, gameExpiry, tonToken, reward);
        if (block.chainid == 31337) {
            MockTON(address(tonToken)).mint(address(rareTitle), reward);
        }
        vm.stopBroadcast();
        console2.log("ton address", address(tonToken));
        console2.log(
            "balance of RareTitle:",
            tonToken.balanceOf(address(rareTitle))
        );
    }

    function run() public returns (RareTitle rareTitle) {
        rareTitle = deployRareTitleUsingConfig();
        console2.log("Deployed RareTitle at:", address(rareTitle));
    }
}
