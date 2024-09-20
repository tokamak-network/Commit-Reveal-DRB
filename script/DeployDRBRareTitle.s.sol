// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {RareTitle} from "src/DRBRareTitle.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {console} from "lib/forge-std/src/console.sol";

contract DeployDRBRareTitle is Script {
    address private drbCoordinator;
    address private tonToken;
    uint256 private gameExpiry;
    uint256 private reward;

    function run() public returns (RareTitle rareTitle) {
        rareTitle = _deployDRBRareTitle();
        console.log("RareTitle game deployed at", address(rareTitle));
    }

    function _deployDRBRareTitle() internal returns (RareTitle _rareTitle) {
        vm.startBroadcast();

        string memory deploymentNetwork = vm.envString("DEPLOYMENT_NETWORK");
        if (bytes(deploymentNetwork).length == 0) {
            revert("Deployment network is not set in .env file");
        }

        if (bytes(vm.envString(string.concat("DRB_COORDINATOR_ADDRESS_", deploymentNetwork))).length == 0) {
            revert("DRBCoordinator address is not set in .env file");
        } else {
            drbCoordinator = vm.envAddress(string.concat("DRB_COORDINATOR_ADDRESS_", deploymentNetwork));
        }

        if (bytes(vm.envString(string.concat("TON_TOKEN_ADDRESS_", deploymentNetwork))).length == 0) {
            revert("TON token address is not set in .env file");
        } else {
            tonToken = vm.envAddress(string.concat("TON_TOKEN_ADDRESS_", deploymentNetwork));
        }

        if (bytes(vm.envString(string.concat("RARE_TITLE_GAME_EXPIRY_", deploymentNetwork))).length == 0) {
            revert("Game expiry is not set in .env file");
        } else {
            gameExpiry = vm.envUint(string.concat("RARE_TITLE_GAME_EXPIRY_", deploymentNetwork));
        }

        if (bytes(vm.envString(string.concat("RARE_TITLE_TON_REWARD_", deploymentNetwork))).length == 0) {
            revert("TON reward is not set in .env file");
        } else {
            reward = vm.envUint(string.concat("RARE_TITLE_TON_REWARD_", deploymentNetwork));
        }

        _rareTitle = new RareTitle(drbCoordinator, gameExpiry, IERC20(tonToken), reward);
        vm.stopBroadcast();
    }
}
