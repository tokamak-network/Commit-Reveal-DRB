pragma solidity ^0.8.26;

import {DRBCoordinator} from "../../src/DRBCoordinator.sol";
import {BaseTest} from "../shared/BaseTest.t.sol";

abstract contract DRBCoordinatorStorageTest is BaseTest {
    DRBCoordinator public s_drbCoordinator;
    address[] s_operatorAddresses;
    address[] s_consumerAddresses;
    uint256 constant s_activationThreshold = 1 ether;
    uint256 s_compensateAmount = 0.2 ether;
    uint256 constant s_flatFee = 0.01 ether;

    function _setUp() internal virtual {
        BaseTest.setUp(); // Start Prank
        vm.txGasPrice(100 gwei);
        vm.deal(OWNER, 10000 ether); // Give some ether to OWNER
        s_operatorAddresses = getRandomAddresses(0, 5);
        s_consumerAddresses = getRandomAddresses(5, 10);
        for (uint256 i = 0; i < s_operatorAddresses.length; i++) {
            vm.deal(s_operatorAddresses[i], 10000 ether);
            vm.deal(s_consumerAddresses[i], 10000 ether);
        }
        s_drbCoordinator = new DRBCoordinator(
            s_activationThreshold,
            s_flatFee,
            s_compensateAmount
        );
        // s_consumerExample = new ConsumerExample(address(s_drbCoordinator));

        // ** set L1
        s_drbCoordinator.setL1FeeCalculation(3, 100);
    }
}
