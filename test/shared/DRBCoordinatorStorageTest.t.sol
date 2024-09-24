pragma solidity ^0.8.26;

import {DRBCoordinator} from "../../src/DRBCoordinator.sol";
import {BaseTest} from "../shared/BaseTest.t.sol";
import {NetworkHelperConfig} from "../../script/NetworkHelperConfig.s.sol";
import {RareTitle} from "../../src/DRBRareTitle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract DRBCoordinatorStorageTest is BaseTest {
    DRBCoordinator public s_drbCoordinator;
    address[] public s_operatorAddresses;
    address[] public s_consumerAddresses;
    uint256 public s_activationThreshold;
    uint256 public s_compensateAmount;
    uint256 public s_flatFee;
    uint256 public s_gameExpiry;
    IERC20 public s_tonToken;
    uint256 public s_reward;
    RareTitle public s_rareTitle;

    function _setUp() internal virtual {
        BaseTest.setUp(); // Start Prank
        if (block.chainid == 31337) vm.txGasPrice(100 gwei);
        vm.deal(OWNER, 10000 ether); // Give some ether to OWNER
        s_operatorAddresses = getRandomAddresses(0, 5);
        s_consumerAddresses = getRandomAddresses(5, 10);
        for (uint256 i = 0; i < s_operatorAddresses.length; i++) {
            vm.deal(s_operatorAddresses[i], 10000 ether);
            vm.deal(s_consumerAddresses[i], 10000 ether);
        }

        NetworkHelperConfig networkHelperConfig = new NetworkHelperConfig();
        uint256 l1GasCostMode;
        (
            s_activationThreshold,
            s_compensateAmount,
            s_flatFee,
            l1GasCostMode,
            s_gameExpiry,
            s_tonToken,
            s_reward
        ) = networkHelperConfig.activeNetworkConfig();
        s_drbCoordinator = new DRBCoordinator(
            s_activationThreshold,
            s_flatFee,
            s_compensateAmount
        );
        (uint8 mode, ) = s_drbCoordinator.getL1FeeCalculationMode();
        if (uint256(mode) != l1GasCostMode) {
            s_drbCoordinator.setL1FeeCalculation(uint8(l1GasCostMode), 100);
        }

        s_rareTitle = new RareTitle(
            address(s_drbCoordinator),
            s_gameExpiry,
            s_tonToken,
            s_reward
        );
    }
}
