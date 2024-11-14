// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {Script, console2} from "forge-std/Script.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {DRBCoordinator} from "../src/DRBCoordinator.sol";
import {ConsumerExample} from "../src/ConsumerExample.sol";
import {RareTitle} from "../src/DRBRareTitle.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

contract Utils is Script {
    address[10] public anvilDefaultAddresses = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,
        0x90F79bf6EB2c4f870365E785982E1f101E93b906,
        0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65,
        0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc,
        0x976EA74026E726554dB657fA54763abd0C3a0aa9,
        0x14dC79964da2C08b23698B3D3cc7Ca32193d9955,
        0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f,
        0xa0Ee7A142d267C1f36714E4a8F75612F20a79720
    ];
    uint256[10] public anvilDefaultPrivateKeys = [
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80,
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d,
        0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a,
        0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6,
        0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a,
        0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba,
        0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e,
        0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356,
        0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97,
        0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6
    ];

    function getContracts()
        public
        view
        returns (DRBCoordinator drbCoordinator, ConsumerExample consumerExample)
    {
        drbCoordinator = DRBCoordinator(
            DevOpsTools.get_most_recent_deployment(
                "DRBCoordinator",
                block.chainid
            )
        );
        consumerExample = ConsumerExample(
            payable(
                DevOpsTools.get_most_recent_deployment(
                    "ConsumerExample",
                    block.chainid
                )
            )
        );
    }
}

contract SetL1FeeCalculation is Utils {
    function run() public {
        (DRBCoordinator drbCoordinator, ) = getContracts();
        uint256 deployer = anvilDefaultPrivateKeys[0];
        uint256 chainid = block.chainid;
        vm.startBroadcast(deployer);
        if (chainid == 31337) {
            drbCoordinator.setL1FeeCalculation(3, 100);
        }
        vm.stopBroadcast();
    }
}

contract ThreeDepositAndActivate is Utils {
    function run() public {
        (DRBCoordinator drbCoordinator, ) = getContracts();
        uint256 minDeposit = drbCoordinator.getMinDeposit();
        for (uint256 i = 0; i < 3; i++) {
            uint256 deployer = anvilDefaultPrivateKeys[i];
            vm.startBroadcast(deployer);
            drbCoordinator.depositAndActivate{value: minDeposit * 10}();
            vm.stopBroadcast();
        }
        uint256 activatedOperatorsLength = drbCoordinator
            .getActivatedOperatorsLength();
        console2.log("Activated operators length:", activatedOperatorsLength);
    }
}

contract TwoDepositAndActivateRealNetwork is Utils {
    // Convert an hexadecimal character to their value
    function fromHexChar(uint8 c) public pure returns (uint8) {
        if (bytes1(c) >= bytes1("0") && bytes1(c) <= bytes1("9")) {
            return c - uint8(bytes1("0"));
        }
        if (bytes1(c) >= bytes1("a") && bytes1(c) <= bytes1("f")) {
            return 10 + c - uint8(bytes1("a"));
        }
        if (bytes1(c) >= bytes1("A") && bytes1(c) <= bytes1("F")) {
            return 10 + c - uint8(bytes1("A"));
        }
        revert("fail");
    }

    // Convert an hexadecimal string to raw bytes
    function fromHex(string memory s) public pure returns (bytes memory) {
        bytes memory ss = bytes(s);
        require(ss.length % 2 == 0); // length must be even
        bytes memory r = new bytes(ss.length / 2);
        for (uint i = 0; i < ss.length / 2; ++i) {
            r[i] = bytes1(
                fromHexChar(uint8(ss[2 * i])) *
                    16 +
                    fromHexChar(uint8(ss[2 * i + 1]))
            );
        }
        return r;
    }

    function run() public {
        (DRBCoordinator drbCoordinator, ) = getContracts();
        uint256 minDeposit = drbCoordinator.getMinDeposit();
        //string memory key = "PRIVATE_KEY";
        string memory key2 = "PRIVATE_KEY2";
        // vm.startBroadcast(uint256(bytes32(fromHex(vm.envString(key)))));
        // drbCoordinator.depositAndActivate{value: minDeposit * 6}();
        // vm.stopBroadcast();
        vm.startBroadcast(uint256(bytes32(fromHex(vm.envString(key2)))));
        drbCoordinator.depositAndActivate{value: minDeposit * 6}();
        vm.stopBroadcast();

        uint256 activatedOperatorsLength = drbCoordinator
            .getActivatedOperatorsLength();
        console2.log("Activated operators length:", activatedOperatorsLength);
    }
}

contract ConsumerRequestRandomNumber is Utils {
    function run() public {
        (
            DRBCoordinator drbCoordinator,
            ConsumerExample consumerExample
        ) = getContracts();
        uint256 deployer = anvilDefaultPrivateKeys[0];
        uint256 callbackGasLimit = consumerExample.CALLBACK_GAS_LIMIT();
        uint256 cost = drbCoordinator.estimateRequestPrice(
            callbackGasLimit,
            tx.gasprice
        );
        vm.startBroadcast(deployer);
        consumerExample.requestRandomNumber{value: cost}();
        vm.stopBroadcast();
        uint256 lastRequestId = consumerExample.lastRequestId();
        console2.log("requested ID:", lastRequestId);
    }

    function run(address consumerExampleAddress) public {
        (DRBCoordinator drbCoordinator, ) = getContracts();
        ConsumerExample consumerExample = ConsumerExample(
            payable(consumerExampleAddress)
        );
        uint256 callbackGasLimit = consumerExample.CALLBACK_GAS_LIMIT();
        uint256 cost = drbCoordinator.estimateRequestPrice(
            callbackGasLimit,
            tx.gasprice
        );
        vm.startBroadcast();
        consumerExample.requestRandomNumber{value: cost}();
        vm.stopBroadcast();
        uint256 lastRequestId = consumerExample.lastRequestId();
        console2.log("requested ID:", lastRequestId);
    }
}

contract Commit is Utils {
    function run(uint256 round) public {
        (DRBCoordinator drbCoordinator, ) = getContracts();
        uint256 commitLength = drbCoordinator.getCommitsLength(round);
        uint256 operator = anvilDefaultPrivateKeys[commitLength];

        vm.startBroadcast(operator);
        drbCoordinator.commit(round, keccak256(abi.encodePacked(commitLength)));
        vm.stopBroadcast();
        uint256 commitLengthAfter = drbCoordinator.getCommitsLength(round);
        console2.log("commit length at round:", round, ": ", commitLengthAfter);
    }

    function run(uint256 round, address drbCoordinatorAddress) public {
        DRBCoordinator drbCoordinator = DRBCoordinator(drbCoordinatorAddress);
        uint256 commitLength = drbCoordinator.getCommitsLength(round);
        vm.startBroadcast();
        drbCoordinator.commit(round, keccak256(abi.encodePacked(commitLength)));
        vm.stopBroadcast();
        uint256 commitLengthAfter = drbCoordinator.getCommitsLength(round);
        console2.log("commit length at round:", round, ": ", commitLengthAfter);
    }
}

contract Reveal is Utils {
    using stdStorage for StdStorage;

    function run(uint256 round) public {
        (DRBCoordinator drbCoordinator, ) = getContracts();
        uint256 revealLength = drbCoordinator.getRevealsLength(round);
        uint256 operator = anvilDefaultPrivateKeys[revealLength];
        DRBCoordinator.RoundInfo memory roundInfo = drbCoordinator.getRoundInfo(
            round
        );
        uint256 commitEndTime = roundInfo.commitEndTime;

        console2.log("commit end time:", commitEndTime);
        console2.log("current time:", block.timestamp);

        vm.startBroadcast(operator);
        drbCoordinator.reveal(round, bytes32(revealLength));
        vm.stopBroadcast();
        uint256 commitLength = drbCoordinator.getCommitsLength(round);
        uint256 revealLengthAfter = drbCoordinator.getRevealsLength(round);
        console2.log("commit length at round:", round, ": ", commitLength);
        console2.log("reveal length at round:", round, ": ", revealLengthAfter);
        if (commitLength == revealLengthAfter) {
            console2.log("All operators have revealed");
            roundInfo = drbCoordinator.getRoundInfo(round);
            console2.log(
                "round:",
                round,
                " random number:",
                roundInfo.randomNumber
            );
            roundInfo = drbCoordinator.getRoundInfo(round);
            console2.log("fulfill succeed?:", roundInfo.fulfillSucceeded);
        }
    }

    function run(uint256 round, address drbCoordinatorAddress) public {
        DRBCoordinator drbCoordinator = DRBCoordinator(drbCoordinatorAddress);
        DRBCoordinator.RoundInfo memory roundInfo = drbCoordinator.getRoundInfo(
            round
        );
        uint256 commitEndTime = roundInfo.commitEndTime;

        console2.log("commit end time:", commitEndTime);
        console2.log("current time:", block.timestamp);

        uint256 commitOrder = drbCoordinator.getCommitOrder(round, msg.sender);

        vm.startBroadcast();
        drbCoordinator.reveal(round, bytes32(commitOrder - 1));
        vm.stopBroadcast();
        uint256 commitLength = drbCoordinator.getCommitsLength(round);
        uint256 revealLengthAfter = drbCoordinator.getRevealsLength(round);
        console2.log("commit length at round:", round, ": ", commitLength);
        console2.log("reveal length at round:", round, ": ", revealLengthAfter);
        if (commitLength == revealLengthAfter) {
            console2.log("All operators have revealed");
            roundInfo = drbCoordinator.getRoundInfo(round);
            console2.log(
                "round:",
                round,
                " random number:",
                roundInfo.randomNumber
            );
        }
    }

    function run(
        uint256 round,
        address drbCoordinatorAddress,
        address msgSender,
        bytes32 reveal
    ) public {
        DRBCoordinator drbCoordinator = DRBCoordinator(drbCoordinatorAddress);
        RareTitle rareTitle = RareTitle(
            payable(address(0xCB01f0f7fC79Ef34e480a6a008C2895bd5a6AF7F))
        );
        DRBCoordinator.RoundInfo memory roundInfo = drbCoordinator.getRoundInfo(
            round
        );
        uint256 commitEndTime = roundInfo.commitEndTime;

        console2.log("commit end time:", commitEndTime);
        console2.log("current time:", block.timestamp);
        //console2.logBytes(address(rareTitle).code);
        console2.log("-----------------");
        // console2.log(
        //     stdstore
        //         .target(address(drbCoordinator))
        //         .sig("s_requestInfo(uint256)")
        //         .with_key(uint256(104))
        //         .depth(3)
        //         .read_uint()
        // );
        vm.store(
            address(drbCoordinator),
            bytes32(uint256(keccak256(abi.encode(104, 4))) + 3),
            bytes32(uint256(160000))
        );
        // stdstore
        //     .target(address(drbCoordinator))
        //     .sig("s_requestInfo(uint256)")
        //     .with_key(uint256(104))
        //     .depth(3)
        //     .checked_write(170000);
        vm.startBroadcast(msgSender);
        drbCoordinator.reveal(round, reveal);
        vm.stopBroadcast();
        uint256 commitLength = drbCoordinator.getCommitsLength(round);
        uint256 revealLengthAfter = drbCoordinator.getRevealsLength(round);
        console2.log("commit length at round:", round, ": ", commitLength);
        console2.log("reveal length at round:", round, ": ", revealLengthAfter);
        if (commitLength == revealLengthAfter) {
            console2.log("All operators have revealed");
            roundInfo = drbCoordinator.getRoundInfo(round);
            console2.log(
                "round:",
                round,
                " random number:",
                roundInfo.randomNumber
            );
        }

        vm.startBroadcast(msgSender);
        (
            address player,
            uint256 randomNumber,
            RareTitle.RequestStatus status
        ) = rareTitle.s_requests(104);
        vm.stopBroadcast();
        console2.log("player:", player, "random number:", randomNumber);
        console2.log("status:", uint256(status));
    }
}

contract IncreaseTime is Utils {
    function run(uint256 secondsToIncrease) public {
        string[] memory inputs = new string[](6);
        inputs[0] = "cast";
        inputs[1] = "rpc";
        inputs[2] = "--rpc-url";
        inputs[3] = "http://localhost:8545";
        inputs[4] = "evm_increaseTime";
        inputs[5] = Strings.toString(secondsToIncrease);
        vm.ffi(inputs);
        string[] memory inputs2 = new string[](5);
        inputs2[0] = "cast";
        inputs2[1] = "rpc";
        inputs2[2] = "--rpc-url";
        inputs2[3] = "http://localhost:8545";
        inputs2[4] = "evm_mine";
        vm.ffi(inputs2);
        //vm.roll(block.number + 1);
        console2.log("Increased time by:", secondsToIncrease);
    }
}

contract GetDepositAmount is Utils {
    function run() public view {
        DRBCoordinator drbCoordinator = DRBCoordinator(
            address(0x78ACCa4E8269E6082D1C78B7386366feb7865fb4)
        );
        address[3] memory operators = [
            address(0xE0bB22e4CEFd5947747D8beF242038A7D4466670),
            address(0x026510c75290c6ef53027494F1b784D8982F5441),
            address(0x90813D87f16df9dF6275420E73ED585e0d906988)
        ];
        for (uint256 i = 0; i < operators.length; i++) {
            uint256 depositAmount = drbCoordinator.getDepositAmount(
                operators[i]
            );
            console2.log(
                "Deposit amount for operator:",
                operators[i],
                depositAmount
            );
        }
        // ETH balance
        for (uint256 i = 0; i < operators.length; i++) {
            console2.log(
                "ETH balance for operator:",
                operators[i],
                address(operators[i]).balance
            );
        }
    }
}

contract Refund is Utils {
    function run(uint256 round) public {
        (, ConsumerExample consumerExample) = getContracts();
        uint256 deployer = anvilDefaultPrivateKeys[0];
        uint256 consumerBalanceBefore = address(consumerExample).balance;
        vm.startBroadcast(deployer);
        consumerExample.getRefund(round);
        vm.stopBroadcast();
        uint256 consumerBalanceAfter = address(consumerExample).balance;
        console2.log(
            "Consumer balance before refund:",
            consumerBalanceBefore,
            "after refund:",
            consumerBalanceAfter
        );
    }
}
