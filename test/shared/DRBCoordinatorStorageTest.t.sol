pragma solidity ^0.8.26;

import {DRBCoordinator} from "../../src/DRBCoordinator.sol";
import {BaseTest} from "../shared/BaseTest.t.sol";
import {NetworkHelperConfig} from "../../script/NetworkHelperConfig.s.sol";

abstract contract DRBCoordinatorStorageTest is BaseTest {
    DRBCoordinator public s_drbCoordinator;
    address[] s_operatorAddresses;
    address[] s_consumerAddresses;
    uint256 s_activationThreshold;
    uint256 s_compensateAmount;
    uint256 s_flatFee;

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
            l1GasCostMode
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
    }
}
