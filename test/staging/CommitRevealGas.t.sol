// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DRBCoordinator} from "../../src/DRBCoordinator.sol";
import {CommitRevealDRB} from "../../src/CommitRevealDRB.sol";
import {console2} from "forge-std/Test.sol";
import {BaseTest} from "../shared/BaseTest.t.sol";
import {NetworkHelperConfig} from "../../script/NetworkHelperConfig.s.sol";
import {ConsumerExample} from "../../src/ConsumerExample.sol";
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {OptimismL1FeesExternal} from "../../src/test/OptimismL1FeesExternal.sol";

contract CommitRevealGasTest is BaseTest {
    using Arrays for uint256[];
    OptimismL1FeesExternal optimismL1FeesExternal;
    DRBCoordinator public s_drbCoordinator;
    CommitRevealDRB public s_commitRevealDRB;
    address[] public s_operatorAddresses;
    uint256 public s_activationThreshold;

    uint256 activationThresholdForCommitReveal = 20301100000000000;

    uint256 public s_compensateAmount;
    uint256 public s_flatFee;
    ConsumerExample s_consumerExample_old;
    ConsumerExample s_consumerExample_new;

    address[3] public anvilDefaultAddresses = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
    ];
    uint256[10] public anvilDefaultPrivateKeys = [
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80,
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d,
        0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
    ];

    function setUp() public override {
        BaseTest.setUp();
        if (block.chainid == 31337) vm.txGasPrice(100 gwei);
        vm.deal(OWNER, 100000000 ether);
        s_operatorAddresses.push(anvilDefaultAddresses[0]);
        s_operatorAddresses.push(anvilDefaultAddresses[1]);
        s_operatorAddresses.push(anvilDefaultAddresses[2]);
        for (uint256 i = 0; i < s_operatorAddresses.length; i++) {
            vm.deal(s_operatorAddresses[i], 100000000 ether);
        }
        NetworkHelperConfig networkHelperConfig = new NetworkHelperConfig();
        uint256 l1GasCostMode;
        (
            s_activationThreshold,
            s_compensateAmount,
            s_flatFee,
            l1GasCostMode,
            ,
            ,

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
        s_commitRevealDRB = new CommitRevealDRB(
            activationThresholdForCommitReveal,
            s_flatFee
        );
        (mode, ) = s_commitRevealDRB.getL1FeeCalculationMode();
        if (uint256(mode) != l1GasCostMode) {
            s_commitRevealDRB.setL1FeeCalculation(uint8(l1GasCostMode), 100);
        }

        s_consumerExample_old = new ConsumerExample(address(s_drbCoordinator));
        s_consumerExample_new = new ConsumerExample(address(s_commitRevealDRB));
    }

    function deposit(address operator) public {
        vm.startPrank(operator);
        s_drbCoordinator.deposit{value: s_activationThreshold}();
        assertEq(
            s_drbCoordinator.getDepositAmount(operator),
            s_activationThreshold
        );
        s_commitRevealDRB.deposit{value: activationThresholdForCommitReveal}();
        assertEq(
            s_commitRevealDRB.s_depositAmount(operator),
            activationThresholdForCommitReveal
        );
        vm.stopPrank();
    }

    function activate(address operator) public {
        vm.startPrank(operator);
        s_drbCoordinator.activate();
        s_commitRevealDRB.activate();
        vm.stopPrank();
        address[] memory activatedOperators = s_drbCoordinator
            .getActivatedOperators();
        assertEq(
            activatedOperators[
                s_drbCoordinator.getActivatedOperatorIndex(operator)
            ],
            operator
        );
        activatedOperators = s_commitRevealDRB.getActivatedOperators();
        assertEq(
            activatedOperators[
                s_commitRevealDRB.s_activatedOperatorOrder(operator)
            ],
            operator
        );
    }

    function test_3Deposits() public {
        vm.stopPrank();
        for (uint256 i = 0; i < s_operatorAddresses.length; i++) {
            deposit(s_operatorAddresses[i]);
        }
        vm.startPrank(OWNER);
    }

    modifier make3Activate() {
        vm.stopPrank();
        for (uint256 i = 0; i < s_operatorAddresses.length; i++) {
            deposit(s_operatorAddresses[i]);
            activate(s_operatorAddresses[i]);
        }
        _;
    }

    function checkBalanceInvariant() public view {
        uint256 balanceOfDRBCoordinator = address(s_drbCoordinator).balance;
        uint256 depositSum;
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            depositSum += s_drbCoordinator.getDepositAmount(
                s_operatorAddresses[i]
            );
        }
        assertEq(
            balanceOfDRBCoordinator / 10,
            depositSum / 10,
            "balanceOfDRBCoordinator invariant assertion"
        );
    }

    function mine() public {
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
    }

    function test_CommitRevealOld() public make3Activate {
        //** 1. requestRandomNumber */
        uint256 callbackGasLimit = s_consumerExample_old.CALLBACK_GAS_LIMIT();
        uint256 cost = s_drbCoordinator.estimateRequestPrice(
            callbackGasLimit,
            tx.gasprice
        );
        s_consumerExample_old.requestRandomNumber{value: cost}();
        uint256 requestId = s_consumerExample_old.lastRequestId();

        /// ** commit
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            address operator = s_operatorAddresses[i];
            vm.startPrank(operator);
            s_drbCoordinator.commit(requestId, keccak256(abi.encodePacked(i)));
            vm.stopPrank();
            mine();

            uint256 commitOrder = s_drbCoordinator.getCommitOrder(
                requestId,
                operator
            );
            assertEq(commitOrder, i + 1);
        }
        DRBCoordinator.RoundInfo memory roundInfo = s_drbCoordinator
            .getRoundInfo(requestId);
        bytes32[] memory commits = s_drbCoordinator.getCommits(requestId);
        assertEq(commits.length, 3);
        assertEq(roundInfo.randomNumber, 0);
        assertEq(roundInfo.fulfillSucceeded, false);

        /// ** 3. reveal
        mine();
        bytes32[] memory reveals = new bytes32[](s_operatorAddresses.length);
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            address operator = s_operatorAddresses[i];
            vm.startPrank(operator);
            s_drbCoordinator.reveal(requestId, bytes32(i));
            reveals[i] = bytes32(i);
            vm.stopPrank();

            uint256 revealOrder = s_drbCoordinator.getRevealOrder(
                requestId,
                operator
            );
            assertEq(revealOrder, i + 1);
        }
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(reveals)));
        bytes32[] memory revealsOnChain = s_drbCoordinator.getReveals(
            requestId
        );
        assertEq(revealsOnChain.length, 3);
        roundInfo = s_drbCoordinator.getRoundInfo(requestId);
        assertEq(roundInfo.randomNumber, randomNumber);
        assertEq(roundInfo.fulfillSucceeded, true);

        for (uint256 i; i < s_operatorAddresses.length; i++) {
            uint256 depositAmount = s_drbCoordinator.getDepositAmount(
                s_operatorAddresses[i]
            );
            if (depositAmount < s_activationThreshold) {
                assertEq(
                    s_drbCoordinator.getActivatedOperatorIndex(
                        s_operatorAddresses[i]
                    ),
                    0
                );
            } else {
                assertEq(
                    s_drbCoordinator.getActivatedOperatorIndex(
                        s_operatorAddresses[i]
                    ),
                    i + 1
                );
            }
        }
        checkBalanceInvariant();

        /// ** run one more time
        s_consumerExample_old.requestRandomNumber{value: cost}();
        requestId = s_consumerExample_old.lastRequestId();
        for (uint256 i; i < 2; i++) {
            address operator = s_operatorAddresses[i];
            vm.startPrank(operator);
            s_drbCoordinator.commit(requestId, keccak256(abi.encodePacked(i)));
            vm.stopPrank();
        }
        vm.warp(block.timestamp + 301);
        mine();
        for (uint256 i; i < 2; i++) {
            address operator = s_operatorAddresses[i];
            vm.startPrank(operator);
            s_drbCoordinator.reveal(requestId, bytes32(i));
            vm.stopPrank();
        }

        checkBalanceInvariant();
    }

    function bytes32Lt(bytes32 a, bytes32 b) public pure returns (bool) {
        return uint256(a) < uint256(b);
    }

    function testCommitRevealNew() public make3Activate {
        /// *** 1. requestRandomNumber
        uint256 callbackGasLimit = s_consumerExample_new.CALLBACK_GAS_LIMIT();
        uint256 cost = s_commitRevealDRB.estimateRequestPrice(
            callbackGasLimit,
            tx.gasprice
        );
        s_consumerExample_new.requestRandomNumber{value: cost}();
        uint256 requestId = s_consumerExample_new.lastRequestId();

        /// ** Off-chain commit phase

        bytes32[] memory secrets = new bytes32[](s_operatorAddresses.length);
        secrets[
            0
        ] = hex"1111111111111111111111111111111111111111111111111111111111111111";
        secrets[
            1
        ] = hex"2222222222222222222222222222222222222222222222222222222222222222";
        secrets[
            2
        ] = hex"3333333333333333333333333333333333333333333333333333333333333333";
        uint8[] memory vs = new uint8[](s_operatorAddresses.length);
        bytes32[] memory rs = new bytes32[](s_operatorAddresses.length);
        bytes32[] memory ss = new bytes32[](s_operatorAddresses.length);
        bytes32[] memory reveals = new bytes32[](s_operatorAddresses.length);
        bytes32[] memory leaves = new bytes32[](s_operatorAddresses.length);
        for (uint256 i; i < s_operatorAddresses.length; i++) {
            (vs[i], rs[i], ss[i]) = vm.sign(
                anvilDefaultPrivateKeys[i],
                bytes32(requestId)
            );
            reveals[i] = rs[i];
            leaves[i] = keccak256(
                abi.encode(keccak256(abi.encode(secrets[i], rs[i])))
            );
        }
        uint256[] memory uintReveals = new uint256[](reveals.length);
        for (uint256 i; i < reveals.length; i++) {
            uintReveals[i] = uint256(reveals[i]);
        }
        uint256[] memory sortedUintReveals = new uint256[](uintReveals.length);
        for (uint256 i = 0; i < sortedUintReveals.length; i++) {
            sortedUintReveals[i] = uintReveals[i];
        }
        sortedUintReveals.sort();
        uint256[] memory revealOrders = new uint256[](sortedUintReveals.length);
        for (uint256 i; i < sortedUintReveals.length; i++) {
            for (uint256 j; j < uintReveals.length; j++) {
                if (uintReveals[j] == sortedUintReveals[i]) {
                    revealOrders[i] = j;
                    break;
                }
            }
        }

        /// *** Onchain Merkle Root submission
        bytes32 merkleRoot = s_commitRevealDRB.createMerkleRootExternal(leaves);
        vm.stopPrank();
        vm.startPrank(s_operatorAddresses[0]);
        s_commitRevealDRB.submitMerkleRoot(requestId, merkleRoot);
        vm.stopPrank();
        mine();

        vm.startPrank(s_operatorAddresses[1]);
        s_commitRevealDRB.generateRandomNumber(
            requestId,
            secrets,
            vs,
            rs,
            ss,
            revealOrders
        );
        vm.stopPrank();

        mine();
        (, uint256 randomNumber, bool fulfillSucceeded) = s_commitRevealDRB
            .s_roundInfo(requestId);
        console2.log("roundInfo.randomNumber", randomNumber);
        assertEq(fulfillSucceeded, true);
    }

    function getAverage(
        uint256[1000] memory data
    ) public pure returns (uint256) {
        uint256 sum;
        for (uint256 i; i < 1000; i++) {
            sum += data[i];
        }
        return sum / 1000;
    }

    function testGas_CommitRevealOld() public make3Activate {
        uint256[1000] memory gasUsedRequestRandomNumber;
        uint256[1000][3] memory gasUsedCommit;
        uint256[1000][3] memory gasUsedReveal;
        for (uint256 t = 0; t < 1000; t++) {
            uint256 callbackGasLimit = s_consumerExample_old
                .CALLBACK_GAS_LIMIT();
            uint256 cost = s_drbCoordinator.estimateRequestPrice(
                callbackGasLimit,
                tx.gasprice
            );
            s_consumerExample_old.requestRandomNumber{value: cost}();
            gasUsedRequestRandomNumber[t] = vm.lastCallGas().gasTotalUsed;
            uint256 requestId = s_consumerExample_old.lastRequestId();
            for (uint256 i; i < s_operatorAddresses.length; i++) {
                address operator = s_operatorAddresses[i];
                vm.startPrank(operator);
                s_drbCoordinator.commit(
                    requestId,
                    keccak256(abi.encodePacked(i))
                );
                vm.stopPrank();
                gasUsedCommit[i][t] = vm.lastCallGas().gasTotalUsed;
            }
            vm.warp(block.timestamp + 301);
            mine();
            for (uint256 i; i < s_operatorAddresses.length; i++) {
                address operator = s_operatorAddresses[i];
                vm.startPrank(operator);
                s_drbCoordinator.reveal(requestId, bytes32(i));
                vm.stopPrank();
                gasUsedReveal[i][t] = vm.lastCallGas().gasTotalUsed;
            }
        }
        console2.log(
            "average gasUsedRequestRandomNumber",
            getAverage(gasUsedRequestRandomNumber)
        );
        for (uint256 i; i < 3; i++) {
            console2.log(
                "average gasUsedCommit",
                i,
                getAverage(gasUsedCommit[i])
            );
        }
        for (uint256 i; i < 3; i++) {
            console2.log(
                "average gasUsedReveal",
                i,
                getAverage(gasUsedReveal[i])
            );
        }
    }

    function testGas_CommitRevealNew() public make3Activate {
        uint256[1000] memory gasUsedRequestRandomNumber;
        uint256[1000] memory gasUsedMerkleRootSubmission;
        uint256[1000] memory gasUsedGenerateRandomNumber;
        uint256 activatedOperatorsLength;
        for (uint256 t; t < 1000; t++) {
            /// *** 1. requestRandomNumber
            uint256 callbackGasLimit = s_consumerExample_new
                .CALLBACK_GAS_LIMIT();
            uint256 cost = s_commitRevealDRB.estimateRequestPrice(
                callbackGasLimit,
                tx.gasprice
            );
            activatedOperatorsLength = s_commitRevealDRB
                .getActivatedOperators()
                .length;
            s_consumerExample_new.requestRandomNumber{value: cost}();
            gasUsedRequestRandomNumber[t] = vm.lastCallGas().gasTotalUsed;
            uint256 requestId = s_consumerExample_new.lastRequestId();

            bytes32[] memory secrets = new bytes32[](
                s_operatorAddresses.length
            );
            secrets[
                0
            ] = hex"1111111111111111111111111111111111111111111111111111111111111111";
            secrets[
                1
            ] = hex"2222222222222222222222222222222222222222222222222222222222222222";
            secrets[
                2
            ] = hex"3333333333333333333333333333333333333333333333333333333333333333";
            uint8[] memory vs = new uint8[](s_operatorAddresses.length);
            bytes32[] memory rs = new bytes32[](s_operatorAddresses.length);
            bytes32[] memory ss = new bytes32[](s_operatorAddresses.length);
            bytes32[] memory reveals = new bytes32[](
                s_operatorAddresses.length
            );
            bytes32[] memory leaves = new bytes32[](s_operatorAddresses.length);
            for (uint256 i; i < s_operatorAddresses.length; i++) {
                (vs[i], rs[i], ss[i]) = vm.sign(
                    anvilDefaultPrivateKeys[i],
                    bytes32(requestId)
                );
                reveals[i] = rs[i];
                leaves[i] = keccak256(
                    abi.encode(keccak256(abi.encode(secrets[i], rs[i])))
                );
            }
            uint256[] memory uintReveals = new uint256[](reveals.length);
            for (uint256 i; i < reveals.length; i++) {
                uintReveals[i] = uint256(reveals[i]);
            }
            uint256[] memory sortedUintReveals = new uint256[](
                uintReveals.length
            );
            for (uint256 i = 0; i < sortedUintReveals.length; i++) {
                sortedUintReveals[i] = uintReveals[i];
            }
            sortedUintReveals.sort();
            uint256[] memory revealOrders = new uint256[](
                sortedUintReveals.length
            );
            for (uint256 i; i < sortedUintReveals.length; i++) {
                for (uint256 j; j < uintReveals.length; j++) {
                    if (uintReveals[j] == sortedUintReveals[i]) {
                        revealOrders[i] = j;
                        break;
                    }
                }
            }

            bytes32 merkleRoot = s_commitRevealDRB.createMerkleRootExternal(
                leaves
            );
            vm.stopPrank();
            vm.startPrank(s_operatorAddresses[0]);
            s_commitRevealDRB.submitMerkleRoot(requestId, merkleRoot);
            vm.stopPrank();
            gasUsedMerkleRootSubmission[t] = vm.lastCallGas().gasTotalUsed;
            mine();
            vm.startPrank(s_operatorAddresses[1]);
            activatedOperatorsLength = s_commitRevealDRB
                .getActivatedOperators()
                .length;
            s_commitRevealDRB.generateRandomNumber(
                requestId,
                secrets,
                vs,
                rs,
                ss,
                revealOrders
            );
            vm.stopPrank();
            gasUsedGenerateRandomNumber[t] = vm.lastCallGas().gasTotalUsed;

            (, uint256 randomNumber, bool fulfillSucceeded) = s_commitRevealDRB
                .s_roundInfo(requestId);
            assertEq(fulfillSucceeded, true);
        }
        console2.log(
            "average gasUsedRequestRandomNumber",
            getAverage(gasUsedRequestRandomNumber)
        );
        console2.log(
            "average gasUsedMerkleRootSubmission",
            getAverage(gasUsedMerkleRootSubmission)
        );
        console2.log(
            "average gasUsedGenerateRandomNumber",
            getAverage(gasUsedGenerateRandomNumber)
        );
    }

    function testGas_Calldata() public {
        string memory key = "OP_MAINNET_RPC_URL";
        string memory OP_MAINNET_RPC_URL = vm.envString(key);
        uint256 optimismFork = vm.createFork(OP_MAINNET_RPC_URL);
        vm.selectFork(optimismFork);

        optimismL1FeesExternal = new OptimismL1FeesExternal();
        //set upperbound
        s_drbCoordinator = new DRBCoordinator(
            s_activationThreshold,
            s_flatFee,
            s_compensateAmount
        );

        /// ** drbCoordinator
        bytes memory requestCalldata = abi.encodeWithSelector(
            s_drbCoordinator.requestRandomNumber.selector,
            2 ** 128 - 1
        );
        bytes memory commitCalldata = abi.encodeWithSelector(
            s_drbCoordinator.commit.selector,
            2 ** 128 - 1,
            keccak256(abi.encodePacked(uint256(2 ** 128 - 1)))
        );
        bytes memory revealCalldata = abi.encodeWithSelector(
            s_drbCoordinator.reveal.selector,
            2 ** 128 - 1,
            bytes32(uint256(2 ** 128 - 1))
        );
        uint256 gasUsedRequest = optimismL1FeesExternal
            .getL1CostWeiForCalldataSize(requestCalldata.length);
        uint256 gasUsedCommit = optimismL1FeesExternal
            .getL1CostWeiForCalldataSize(commitCalldata.length);
        uint256 gasUsedReveal = optimismL1FeesExternal
            .getL1CostWeiForCalldataSize(revealCalldata.length);
        console2.log("gasUsedRequest gas", gasUsedRequest);
        console2.log("gasUsedRequest calldata size", requestCalldata.length);
        console2.log("gasUsedCommit gas", gasUsedCommit);
        console2.log("gasUsedCommit calldata size", commitCalldata.length);

        console2.log("gasUsedReveal gas", gasUsedReveal);
        console2.log("gasUsedReveal calldata size", revealCalldata.length);

        /// ** commitRevealDRB
        s_commitRevealDRB = new CommitRevealDRB(
            activationThresholdForCommitReveal,
            s_flatFee
        );
        requestCalldata = abi.encodeWithSelector(
            s_commitRevealDRB.requestRandomNumber.selector,
            2 ** 128 - 1
        );
        bytes memory merkleRootSubmissionCalldata = abi.encodeWithSelector(
            s_commitRevealDRB.submitMerkleRoot.selector,
            2 ** 128 - 1,
            keccak256(abi.encode(uint256(2 ** 128 - 1)))
        );

        bytes32[] memory secrets = new bytes32[](s_operatorAddresses.length);
        secrets[
            0
        ] = hex"1111111111111111111111111111111111111111111111111111111111111111";
        secrets[
            1
        ] = hex"2222222222222222222222222222222222222222222222222222222222222222";
        secrets[
            2
        ] = hex"3333333333333333333333333333333333333333333333333333333333333333";
        uint8[] memory vs = new uint8[](s_operatorAddresses.length);
        bytes32[] memory rs = new bytes32[](s_operatorAddresses.length);
        bytes32[] memory ss = new bytes32[](s_operatorAddresses.length);
        bytes32[] memory reveals = new bytes32[](s_operatorAddresses.length);
        bytes32[] memory leaves = new bytes32[](s_operatorAddresses.length);

        for (uint256 i; i < s_operatorAddresses.length; i++) {
            (vs[i], rs[i], ss[i]) = vm.sign(
                anvilDefaultPrivateKeys[i],
                bytes32(uint256(1))
            );
            reveals[i] = rs[i];
            leaves[i] = keccak256(
                abi.encode(keccak256(abi.encode(secrets[i], rs[i])))
            );
        }
        uint256[] memory uintReveals = new uint256[](reveals.length);
        for (uint256 i; i < reveals.length; i++) {
            uintReveals[i] = uint256(reveals[i]);
        }
        uint256[] memory sortedUintReveals = new uint256[](uintReveals.length);
        for (uint256 i = 0; i < sortedUintReveals.length; i++) {
            sortedUintReveals[i] = uintReveals[i];
        }
        sortedUintReveals.sort();
        uint256[] memory revealOrders = new uint256[](sortedUintReveals.length);
        for (uint256 i; i < sortedUintReveals.length; i++) {
            for (uint256 j; j < uintReveals.length; j++) {
                if (uintReveals[j] == sortedUintReveals[i]) {
                    revealOrders[i] = j;
                    break;
                }
            }
        }

        bytes32 merkleRoot = s_commitRevealDRB.createMerkleRootExternal(leaves);

        bytes memory generateRandomNumberCalldata = abi.encodeWithSelector(
            s_commitRevealDRB.generateRandomNumber.selector,
            2 ** 128 - 1,
            secrets,
            vs,
            rs,
            ss,
            revealOrders
        );

        uint256 gasUsedRequestCommitReveal = optimismL1FeesExternal
            .getL1CostWeiForCalldataSize(requestCalldata.length);
        uint256 gasUsedMerkleRootSubmission = optimismL1FeesExternal
            .getL1CostWeiForCalldataSize(merkleRootSubmissionCalldata.length);
        uint256 gasUsedGenerateRandomNumber = optimismL1FeesExternal
            .getL1CostWeiForCalldataSize(generateRandomNumberCalldata.length);
        console2.log("request gas", gasUsedRequestCommitReveal);
        console2.log("request calldata size", requestCalldata.length);
        console2.log(
            "gasUsedMerkleRootSubmission gas",
            gasUsedMerkleRootSubmission
        );
        console2.log(
            "gasUsedGenerateRandomNumber calldata size",
            merkleRootSubmissionCalldata.length
        );
        console2.log(
            "gasUsedGenerateRandomNumber gas",
            gasUsedGenerateRandomNumber
        );
        console2.log(
            "gasUsedGenerateRandomNumber calldata size",
            generateRandomNumberCalldata.length
        );
        console2.logBytes(generateRandomNumberCalldata);
    }

    function testGas_DoubleHashAndMoreInput() public {
        // Double Hash
        bytes32 data = hex"1111111111111111111111111111111111111111111111111111111111111111";
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            anvilDefaultPrivateKeys[0],
            data
        );
        vm.startSnapshotGas("moreInputs");
        bytes32 hash2 = keccak256(abi.encode(data, r, s));
        vm.stopSnapshotGas();

        vm.startSnapshotGas("doubleHash");
        bytes32 hash1 = keccak256(bytes.concat(keccak256(abi.encode(data, r))));
        vm.stopSnapshotGas();
    }

    function testGas_Original_Hybrid() public {
        string[] memory keys = new string[](3);
        keys[0] = vm.envString("OP_MAINNET_RPC_URL");
        keys[1] = vm.envString("THANOS_SEPOLIA_URL");
        keys[2] = vm.envString("TITAN_RPC_URL");
        string[2] memory networks = [
            "OP_MAINNET_RPC_URL",
            "THANOS_SEPOLIA_URL"
        ];

        uint256[] memory ns = new uint256[](79);
        for (uint256 i = 2; i < 81; i++) {
            ns[i - 2] = i;
        }

        for (uint256 i; i < 2; i++) {
            uint256 fork = vm.createFork(keys[i]);
            vm.selectFork(fork);
            optimismL1FeesExternal = new OptimismL1FeesExternal();
            console2.log(networks[i], "fork");
            for (uint256 j; j < 79; j++) {
                console2.log("N:", ns[j]);
                uint256 totalGasCostOriginal = optimismL1FeesExternal
                    .getL1CostWeiForCalldataSize(68) *
                    2 *
                    ns[j];
                uint256 totalGasCostHybrid = optimismL1FeesExternal
                    .getL1CostWeiForCalldataSize(68) +
                    optimismL1FeesExternal.getL1CostWeiForCalldataSize(
                        356 + (160 * ns[j])
                    );
                console2.log("totalGasCostOriginal", totalGasCostOriginal);
                console2.log("totalGasCostHybrid", totalGasCostHybrid);
            }
        }

        uint256 fork = vm.createFork(keys[2]);
        vm.selectFork(fork);
        optimismL1FeesExternal = new OptimismL1FeesExternal();
        console2.log("TITAN", "fork");
        for (uint256 j; j < 9; j++) {
            console2.log("N:", ns[j]);
            uint256 totalGasCostOriginal = optimismL1FeesExternal
                .getL1CostLegacy(68) * ns[j];
            uint256 totalGasCostHybrid = optimismL1FeesExternal.getL1CostLegacy(
                68
            ) + optimismL1FeesExternal.getL1CostLegacy(356 + (160 * ns[j]));
            console2.log("totalGasCostOriginal", totalGasCostOriginal);
            console2.log("totalGasCostHybrid", totalGasCostHybrid);
        }
    }

    function testGas_2Original_Hybrid() public {
        string[] memory keys = new string[](3);
        keys[0] = vm.envString("OP_MAINNET_RPC_URL");
        keys[1] = vm.envString("THANOS_SEPOLIA_URL");
        keys[2] = vm.envString("TITAN_RPC_URL");
        string[2] memory networks = [
            "OP_MAINNET_RPC_URL",
            "THANOS_SEPOLIA_URL"
        ];

        uint256[] memory ns = new uint256[](59);
        for (uint256 i = 2; i < 61; i++) {
            ns[i - 2] = i;
        }
        for (uint256 i; i < 2; i++) {
            uint256 fork = vm.createFork(keys[i]);
            vm.selectFork(fork);
            optimismL1FeesExternal = new OptimismL1FeesExternal();
            console2.log(networks[i], "fork");
            for (uint256 j; j < 59; j++) {
                console2.log("N:", ns[j]);
                uint256 totalGasCostOriginal = optimismL1FeesExternal
                    .getL1CostWeiForCalldataSize(68) *
                    2 *
                    ns[j] +
                    optimismL1FeesExternal.getL1CostWeiForCalldataSize(100);
                uint256 totalGasCostHybrid = optimismL1FeesExternal
                    .getL1CostWeiForCalldataSize(68) +
                    optimismL1FeesExternal.getL1CostWeiForCalldataSize(
                        356 + (160 * ns[j])
                    );
                console2.log("totalGasCostOriginal", totalGasCostOriginal);
                console2.log("totalGasCostHybrid", totalGasCostHybrid);
            }
        }

        uint256 fork = vm.createFork(keys[2]);
        vm.selectFork(fork);
        optimismL1FeesExternal = new OptimismL1FeesExternal();
        console2.log("TITAN", "fork");
        for (uint256 j; j < 9; j++) {
            console2.log("N:", ns[j]);
            uint256 totalGasCostOriginal = optimismL1FeesExternal
                .getL1CostLegacy(68) *
                2 *
                ns[j] +
                optimismL1FeesExternal.getL1CostLegacy(100);
            uint256 totalGasCostHybrid = optimismL1FeesExternal.getL1CostLegacy(
                68
            ) + optimismL1FeesExternal.getL1CostLegacy(356 + (160 * ns[j]));
            console2.log("totalGasCostOriginal", totalGasCostOriginal);
            console2.log("totalGasCostHybrid", totalGasCostHybrid);
        }
    }

    function test_DoubleHash() public {
        bytes32 data = hex"1111111111111111111111111111111111111111111111111111111111111111";
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            anvilDefaultPrivateKeys[0],
            data
        );
        bytes32 hash1 = keccak256(bytes.concat(keccak256(abi.encode(data, r))));
    }

    function test_MoreInputs() public {
        bytes32 data = hex"1111111111111111111111111111111111111111111111111111111111111111";
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            anvilDefaultPrivateKeys[0],
            data
        );
        bytes32 hash1 = keccak256(abi.encode(data, r, s));
    }

    function generateRandomNumber1(
        uint256 round,
        bytes32[] calldata secrets,
        uint8[] calldata vs,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        uint8[] calldata revealOrders
    ) external {}

    function test_calldataSize() public {
        console2.log(
            abi
                .encodeWithSelector(
                    this.generateRandomNumber1.selector,
                    2 ** 128 - 1,
                    new bytes32[](3),
                    new uint8[](3),
                    new bytes32[](3),
                    new bytes32[](3),
                    new uint8[](3)
                )
                .length
        );
    }
}
