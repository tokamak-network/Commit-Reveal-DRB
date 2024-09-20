// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DRBCoordinator} from "../../src/DRBCoordinator.sol";
import {BaseTest} from "../shared/BaseTest.t.sol";
import {ConsumerExample} from "../../src/ConsumerExample.sol";
import {OptimismL1FeesExternal} from "../../src/test/OptimismL1FeesExternal.sol";
import {ConsumerExampleFulfillRandomWord} from "../../src/test/ConsumerExampleFulfillRandomWord.sol";
import {console2} from "forge-std/Test.sol";
import {NetworkHelperConfig} from "../../script/NetworkHelperConfig.s.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract DRBCoodinatorGasTest is BaseTest {
    DRBCoordinator s_drbCoordinator;
    address[] s_operatorAddresses;
    ConsumerExample s_consumerExample;
    uint256 s_activationThreshold = 1 ether;
    uint256 s_compensationAmount = 0.2 ether;
    uint256 s_flatFee = 0.01 ether;
    ConsumerExampleFulfillRandomWord s_consumerExampleFulfillRandomWord;
    /// @dev L1_FEE_DATA_PADDING inclues 71 bytes for L1 data padding for Optimism
    bytes internal constant L1_FEE_DATA_PADDING =
        hex"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    OptimismL1FeesExternal optimismL1FeesExternal;

    function mine() public {
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
    }

    function setUp() public override {
        BaseTest.setUp(); // Start Prank
        vm.txGasPrice(10 gwei);
        vm.deal(OWNER, 10000 ether); // Give some ether to OWNER
        s_operatorAddresses = getRandomAddresses(0, 7);
        for (uint256 i = 0; i < s_operatorAddresses.length; i++) {
            vm.deal(s_operatorAddresses[i], 10000 ether);
        }
        s_drbCoordinator = new DRBCoordinator(s_activationThreshold, s_flatFee, s_compensationAmount);
        s_consumerExample = new ConsumerExample(address(s_drbCoordinator));
        s_consumerExampleFulfillRandomWord = new ConsumerExampleFulfillRandomWord(address(s_drbCoordinator));
        // ** set L1
        s_drbCoordinator.setL1FeeCalculation(3, 100);
    }

    function getCommitCalldata() public view returns (bytes memory) {
        return abi.encodeWithSelector(
            s_drbCoordinator.commit.selector, 2 ** 128 - 1, keccak256(abi.encodePacked(uint256(2 ** 128 - 1)))
        );
    }

    function getRevealCalldata() public view returns (bytes memory) {
        return abi.encodeWithSelector(s_drbCoordinator.reveal.selector, 2 ** 128 - 1, bytes32(uint256(2 ** 128 - 1)));
    }

    function getRefundCalldata() public view returns (bytes memory) {
        return abi.encodeWithSelector(s_drbCoordinator.getRefund.selector, 2 ** 128 - 1);
    }

    function getRequsetRandomNumberCalldata() public view returns (bytes memory) {
        return abi.encodeWithSelector(s_drbCoordinator.requestRandomNumber.selector, 2500000);
    }

    function get2commitrevealCalldata() public view returns (bytes memory totalCalldata) {
        bytes memory commitData = getCommitCalldata();
        bytes memory revealData = getRevealCalldata();
        totalCalldata = bytes.concat(
            commitData,
            commitData,
            revealData,
            revealData,
            L1_FEE_DATA_PADDING,
            L1_FEE_DATA_PADDING,
            L1_FEE_DATA_PADDING,
            L1_FEE_DATA_PADDING
        );
        console2.log("2commits2reveals calldata size in bytes", totalCalldata.length);
        console2.log(
            "1commit11reveal calldata size in bytes",
            bytes.concat(commitData, revealData, L1_FEE_DATA_PADDING, L1_FEE_DATA_PADDING).length
        );
    }

    function getAllL1FeeCost() public view returns (uint256) {
        return optimismL1FeesExternal.getL1CostWeiForCalldataSize(get2commitrevealCalldata().length);
    }

    function getcommitL1FeeCost() public view returns (uint256) {
        return optimismL1FeesExternal.getL1CostWeiForCalldataSize(getCommitCalldata().length);
    }

    function getrevealL1FeeCost() public view returns (uint256) {
        return optimismL1FeesExternal.getL1CostWeiForCalldataSize(getRevealCalldata().length);
    }

    function testGas_CommitReveal() public {
        uint256 gasUsed;
        // ** make max operators commmit
        uint256 maxActivatedOperators = s_drbCoordinator.getMaxActivatedOperators();
        vm.stopPrank();
        for (uint256 i = 0; i < maxActivatedOperators; i++) {
            address operator = s_operatorAddresses[i];
            uint256 minDeposit = s_drbCoordinator.getMinDeposit();
            vm.startPrank(operator);
            s_drbCoordinator.depositAndActivate{value: minDeposit * 10}();
            vm.stopPrank();
            gasUsed = vm.lastCallGas().gasTotalUsed;
            console2.log("deposit gasUsed", gasUsed);
        }
        console2.log();

        vm.startPrank(OWNER);
        // ** 1. requestRandomNumber 10 times
        uint256 callbackGasLimit = 100000;
        uint256 cost = s_drbCoordinator.estimateRequestPrice(callbackGasLimit, tx.gasprice);
        console2.log("requestRandomNumber cost", cost);
        console2.log();
        for (uint256 i = 0; i < 10; i++) {
            s_consumerExample.requestRandomNumber{value: cost}();
            gasUsed = vm.lastCallGas().gasTotalUsed;
            console2.log("requestRandomNumber gasUsed", gasUsed);
        }
        console2.log();

        // ** 1.1 requestRandomNumber Directly 10 times
        for (uint256 i = 0; i < 10; i++) {
            s_drbCoordinator.requestRandomNumber{value: cost}(uint32(callbackGasLimit));
            gasUsed = vm.lastCallGas().gasTotalUsed;
            console2.log("requestRandomNumber direct gasUsed", gasUsed);
        }

        // ** 2. 2 operators commit 10 rounds
        for (uint256 round = 0; round < 10; round++) {
            for (uint256 i = 0; i < 2; i++) {
                address operator = s_operatorAddresses[i];
                vm.startPrank(operator);
                s_drbCoordinator.commit(round, keccak256(abi.encodePacked(i)));
                vm.stopPrank();
                gasUsed = vm.lastCallGas().gasTotalUsed;
                console2.log("commit gasUsed", gasUsed);
            }
        }

        // ** 3. 2 operators reveal 10 rounds
        vm.warp(block.timestamp + 301);
        mine();
        for (uint256 round = 0; round < 10; round++) {
            for (uint256 i = 0; i < 2; i++) {
                address operator = s_operatorAddresses[i];
                vm.startPrank(operator);
                s_drbCoordinator.reveal(round, bytes32(i));
                vm.stopPrank();
                gasUsed = vm.lastCallGas().gasTotalUsed;
                console2.log("reveal gasUsed", gasUsed);
            }
        }

        // ** Consumer Example fulfill gasUsed
        vm.startPrank(OWNER);
        for (uint256 i; i < 10; i++) {
            s_consumerExampleFulfillRandomWord.rawFulfillRandomWords(i, uint256(keccak256(abi.encodePacked(i))));
            gasUsed = vm.lastCallGas().gasTotalUsed;
            console2.log("fulfillRandomWords gasUsed", gasUsed);
        }

        // ** estimateRequestPrice
        cost = s_drbCoordinator.estimateRequestPrice(100000, tx.gasprice);
        console2.log("estimateRequestPrice cost", cost);
    }

    function testCalldataSize() public {
        string memory key = "OP_MAINNET_RPC_URL";
        string memory OP_MAINNET_RPC_URL = vm.envString(key);
        uint256 optimismFork = vm.createFork(OP_MAINNET_RPC_URL);
        vm.selectFork(optimismFork);

        optimismL1FeesExternal = new OptimismL1FeesExternal();
        //set upperbound
        s_drbCoordinator.setL1FeeCalculation(0, 100);

        bytes memory refundCalldata = getRefundCalldata();
        console2.log("refundCalldata length in bytes", bytes.concat(refundCalldata, L1_FEE_DATA_PADDING).length);

        bytes memory requestRandomNumberCalldata = getRequsetRandomNumberCalldata();
        console2.log(
            "requestRandomNumberCalldata length in bytes",
            bytes.concat(requestRandomNumberCalldata, L1_FEE_DATA_PADDING).length
        );

        uint256 allL1FeeCost = getAllL1FeeCost();
        console2.log("allL1FeeCost", allL1FeeCost);
    }

    function createMaxActivatedOperators() public {
        uint256 maxActivatedOperators = s_drbCoordinator.getMaxActivatedOperators();
        vm.stopPrank();
        for (uint256 i = 0; i < maxActivatedOperators; i++) {
            address operator = s_operatorAddresses[i];
            uint256 minDeposit = s_drbCoordinator.getMinDeposit();
            vm.startPrank(operator);
            s_drbCoordinator.depositAndActivate{value: minDeposit * 10}();
            vm.stopPrank();
        }
    }

    function reqeustRandomNumber10Times() public {
        vm.startPrank(OWNER);
        // ** 1. requestRandomNumber 10 times
        uint256 callbackGasLimit = 100000;
        uint256 cost = s_drbCoordinator.estimateRequestPrice(callbackGasLimit, tx.gasprice);
        for (uint256 i = 0; i < 10; i++) {
            s_consumerExample.requestRandomNumber{value: cost}();
        }
    }

    function testGas_RefundRule1() public {
        createMaxActivatedOperators();
        reqeustRandomNumber10Times();

        // ** increase time
        (uint256 maxWait,,) = s_drbCoordinator.getDurations();
        vm.warp(block.timestamp + maxWait + 1);
        vm.roll(block.number + 1);

        // ** refund 10 times
        for (uint256 i = 0; i < 10; i++) {
            s_consumerExample.getRefund(i);
            uint256 gasUsed = vm.lastCallGas().gasTotalUsed;
            console2.log("refund #1 gasUsed, loop i=", i, gasUsed);
        }
    }

    /// rule 2
    function testGas_RefundRule2() public {
        createMaxActivatedOperators();
        reqeustRandomNumber10Times();

        // ** 1 commit for 10 rounds
        address operator = s_operatorAddresses[0];
        vm.startPrank(operator);
        uint256 c = 0;
        for (uint256 i = 0; i < 10; i++) {
            s_drbCoordinator.commit(i, keccak256(abi.encodePacked(c)));
        }
        vm.stopPrank();
        mine();

        // ** increase time
        (, uint256 commitDuration,) = s_drbCoordinator.getDurations();
        vm.warp(block.timestamp + commitDuration + 1);
        vm.roll(block.number + 1);

        // ** refund 10 times
        for (uint256 i = 0; i < 10; i++) {
            s_consumerExample.getRefund(i);
            uint256 gasUsed = vm.lastCallGas().gasTotalUsed;
            console2.log("refund #2 gasUsed, loop i=", i, gasUsed);
        }
    }

    /// rule 3
    function testGas_RefundRule3() public {
        createMaxActivatedOperators();
        reqeustRandomNumber10Times();

        address operator;

        // ** commits
        for (uint256 requestId = 0; requestId < 10; requestId++) {
            for (uint256 i; i < s_operatorAddresses.length; i++) {
                operator = s_operatorAddresses[i];
                vm.startPrank(operator);
                s_drbCoordinator.commit(requestId, keccak256(abi.encodePacked(i)));
                vm.stopPrank();
            }
        }
        mine();

        // ** 1 reveal, 2 reveals, ... ~ s_operatorAddresses.length - 1 reveal

        for (uint256 requestId = 0; requestId < 10; requestId++) {
            uint256 j = 0;
            for (uint256 i; i < (s_operatorAddresses.length - 1) - j; i++) {
                operator = s_operatorAddresses[i];
                vm.startPrank(operator);
                s_drbCoordinator.reveal(requestId, bytes32(i));
                vm.stopPrank();
                if (requestId < s_operatorAddresses.length - 1) {
                    j++;
                }
            }
        }

        // ** increase time
        (,, uint256 revealDuration) = s_drbCoordinator.getDurations();
        vm.warp(block.timestamp + revealDuration + 1);
        vm.roll(block.number + 1);

        // ** refund 10 times
        for (uint256 i = 0; i < 10; i++) {
            s_consumerExample.getRefund(i);
            uint256 gasUsed = vm.lastCallGas().gasTotalUsed;
            console2.log("refund #3 gasUsed, loop i=", i, gasUsed);
        }
    }

    function castToEtherUnit(uint256 amount) public returns (string memory) {
        string[] memory inputs = new string[](4);
        inputs[0] = "cast";
        inputs[1] = "to-unit";
        inputs[2] = Strings.toString(amount);
        inputs[3] = "ether";
        bytes memory res = vm.ffi(inputs);
        return string(res);
    }

    function testGas_getNetworkConfigs() public {
        string memory key = "TITAN_RPC_URL";
        string memory TITAN_RPC_URL = vm.envString(key);
        uint256 titanFork = vm.createFork(TITAN_RPC_URL);
        key = "TITAN_SEPOLIA_URL";
        string memory TITAN_SEPOLIA_URL = vm.envString(key);
        uint256 titanSepoliaFork = vm.createFork(TITAN_SEPOLIA_URL);
        key = "THANOS_SEPOLIA_URL";
        string memory THANOS_SEPOLIA_URL = vm.envString(key);
        uint256 thanosSepoliaFork = vm.createFork(THANOS_SEPOLIA_URL);

        NetworkHelperConfig networkHelperConfig = new NetworkHelperConfig();

        NetworkHelperConfig.NetworkConfig memory networkConfig;

        networkConfig = networkHelperConfig.getAnvilConfig();
        console2.log("Anvil Config");
        console2.log("activationThreshold(ether)", "compensateAmount(ether)", "flatFee(ether)", "l1GasCostMode");
        console2.log(
            castToEtherUnit(networkConfig.activationThreshold),
            castToEtherUnit(networkConfig.compensateAmount),
            castToEtherUnit(networkConfig.flatFee),
            networkConfig.l1GasCostMode
        );

        vm.selectFork(titanFork);
        networkConfig = networkHelperConfig.getTitanConfig();
        console2.log("Titan Config");
        console2.log("activationThreshold(ether)", "compensateAmount(ether)", "flatFee(ether)", "l1GasCostMode");
        console2.log(
            castToEtherUnit(networkConfig.activationThreshold),
            castToEtherUnit(networkConfig.compensateAmount),
            castToEtherUnit(networkConfig.flatFee),
            networkConfig.l1GasCostMode
        );

        vm.selectFork(titanSepoliaFork);
        networkConfig = networkHelperConfig.getTitanSepoliaConfig();
        console2.log("Titan Sepolia Config");
        console2.log("activationThreshold(ether)", "compensateAmount(ether)", "flatFee(ether)", "l1GasCostMode");
        console2.log(
            castToEtherUnit(networkConfig.activationThreshold),
            castToEtherUnit(networkConfig.compensateAmount),
            castToEtherUnit(networkConfig.flatFee),
            networkConfig.l1GasCostMode
        );

        vm.selectFork(thanosSepoliaFork);
        networkConfig = networkHelperConfig.getThanosSepoliaConfig();
        console2.log("Thanos Sepolia Config");
        console2.log("activationThreshold(TON)", "compensateAmount(TON)", "flatFee(TON)", "l1GasCostMode");
        console2.log(
            castToEtherUnit(networkConfig.activationThreshold),
            castToEtherUnit(networkConfig.compensateAmount),
            castToEtherUnit(networkConfig.flatFee),
            networkConfig.l1GasCostMode
        );
    }
}
