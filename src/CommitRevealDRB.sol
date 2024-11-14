// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {CommitRevealDRBStorage} from "./CommitRevealDRBStorage.sol";
import {OptimismL1Fees} from "./OptimismL1Fees.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DRBConsumerBase} from "./DRBConsumerBase.sol";

contract CommitRevealDRB is
    ReentrancyGuard,
    OptimismL1Fees,
    CommitRevealDRBStorage
{
    constructor(
        uint256 activationThreshold,
        uint256 flatFee
    ) Ownable(msg.sender) {
        s_activationThreshold = activationThreshold;
        s_flatFee = flatFee;
        s_activatedOperators.push(address(0)); // dummy data
    }

    function estimateRequestPrice(
        uint256 callbackGasLimit,
        uint256 gasPrice
    ) external view returns (uint256) {
        return _calculateRequestPrice(callbackGasLimit, gasPrice);
    }

    /// *** consumer external functions
    function requestRandomNumber(
        uint32 callbackGasLimit
    ) external payable nonReentrant returns (uint256 round) {
        require(
            callbackGasLimit <= MAX_CALLBACK_GAS_LIMIT,
            ExceedCallbackGasLimit()
        );
        require(s_activatedOperators.length > 2, NotEnoughActivatedOperators());
        require(
            msg.value >= _calculateRequestPrice(callbackGasLimit, tx.gasprice),
            InsufficientAmount()
        );
        unchecked {
            round = s_nextRound++;
        }
        s_requestInfo[round] = RequestInfo({
            consumer: msg.sender,
            requestedTime: block.timestamp,
            cost: msg.value,
            callbackGasLimit: callbackGasLimit
        });
        address[] memory activatedOperators;
        s_activatedOperatorsAtRound[
            round
        ] = activatedOperators = s_activatedOperators;
        uint256 activatedOperatorsLength = activatedOperators.length;
        uint256 i = 1;
        mapping(address => uint256)
            storage activatedOperatorOrderAtRound = s_activatedOperatorOrderAtRound[
                round
            ];
        uint256 activationThreshold = s_activationThreshold;
        do {
            address operator = activatedOperators[i];
            activatedOperatorOrderAtRound[operator] = i;
            uint256 activatedOperatorIndex = s_activatedOperatorOrder[operator];
            if ((s_depositAmount[operator] -= msg.value) < activationThreshold)
                _deactivate(activatedOperatorIndex, operator);
            unchecked {
                ++i;
            }
        } while (i < activatedOperatorsLength);
        emit RandomNumberRequested(round, activatedOperators);
    }

    function _calculateRequestPrice(
        uint256 callbackGasLimit,
        uint256 gasPrice
    ) private view returns (uint256) {
        return
            (((gasPrice *
                (callbackGasLimit + MERKLEROOTSUB_RANDOMNUMGENERATE_GASUSED)) *
                (s_premiumPercentage + 100)) / 100) +
            s_flatFee +
            _getL1CostWeiForcalldataSize2(
                MERKLEROOTSUB_CALLDATA_BYTES_SIZE,
                RANDOMNUMGENERATE_CALLDATA_BYTES_SIZE
            );
    }

    function _getL1CostWeiForcalldataSize2(
        uint256 calldataSizeBytes1,
        uint256 calldataSizeBytes2
    ) private view returns (uint256) {
        uint8 l1FeeCalculationMode = s_l1FeeCalculationMode;
        if (l1FeeCalculationMode == L1_GAS_FEES_ECOTONE_MODE) {
            // estimate based on unsigned fully RLP-encoded transaction size so we have to account for paddding bytes as well
            return
                _calculateOptimismL1DataFee(
                    calldataSizeBytes1 + L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE
                ) +
                _calculateOptimismL1DataFee(
                    calldataSizeBytes2 + L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE
                );
        } else if (l1FeeCalculationMode == L1_GAS_FEES_UPPER_BOUND_MODE) {
            // getL1FeeUpperBound expects unsigned fully RLP-encoded transaction size so we have to account for paddding bytes as well
            return
                OVM_GASPRICEORACLE.getL1FeeUpperBound(
                    calldataSizeBytes1 + L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE
                ) +
                OVM_GASPRICEORACLE.getL1FeeUpperBound(
                    calldataSizeBytes2 + L1_UNSIGNED_RLP_ENC_TX_DATA_BYTES_SIZE
                );
        } else if (l1FeeCalculationMode == L1_GAS_FEES_LEGACY_MODE)
            return
                _calculateLegacyL1DataFee(calldataSizeBytes1) +
                _calculateLegacyL1DataFee(calldataSizeBytes2);
        else return 0;
    }

    /// *** operators ***
    /// *** operator external functions

    /// *** drb
    function submitMerkleRoot(
        uint256 round,
        bytes32 merkleRoot
    ) external nonReentrant {
        address[]
            storage activatedOperatorsAtRound = s_activatedOperatorsAtRound[
                round
            ];
        require(
            activatedOperatorsAtRound[
                s_activatedOperatorOrderAtRound[round][msg.sender]
            ] == msg.sender,
            NotActivatedOperatorForThisRound()
        );
        s_roundInfo[round].merkleRoot = merkleRoot;
    }

    function generateRandomNumber(
        uint256 round,
        bytes32[] calldata secrets,
        uint8[] calldata vs,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        uint256[] calldata revealOrders
    ) external nonReentrant {
        mapping(address => uint256)
            storage activatedOperatorOrderAtRound = s_activatedOperatorOrderAtRound[
                round
            ];
        uint256 secretsLength = secrets.length;
        bytes32[] memory leaves = new bytes32[](secretsLength);

        // reveal order verification
        for (uint256 i = 1; i < secretsLength; i = unchecked_inc(i)) {
            require(
                rs[revealOrders[i]] > rs[revealOrders[i - 1]],
                RevealNotInAscendingOrder()
            );
        }
        bytes32 roundBytes32 = bytes32(round);
        for (uint256 i; i < secretsLength; i = unchecked_inc(i)) {
            bytes32 leaf = keccak256(
                abi.encode(_efficientKeccak256(secrets[i], rs[i]))
            );
            leaves[i] = leaf; // for verifying the merkle proof
            address recoveredAddress = ecrecover(
                roundBytes32,
                vs[i],
                rs[i],
                ss[i]
            );
            require(
                activatedOperatorOrderAtRound[recoveredAddress] != 0,
                InvalidSignature(recoveredAddress)
            ); // signer(operator) verification
        }
        RoundInfo storage roundInfo = s_roundInfo[round];

        // verify merkle root
        require(
            createMerkleRoot(leaves) == roundInfo.merkleRoot,
            MerkleVerificationFailed()
        );

        // create random number
        bytes memory secretsInRevealOrder = abi.encode(
            secrets[revealOrders[0]],
            secrets[revealOrders[1]]
        );
        for (uint256 i = 2; i < secretsLength; i = unchecked_inc(i)) {
            secretsInRevealOrder = abi.encode(
                secretsInRevealOrder,
                secrets[revealOrders[i]]
            );
        }
        uint256 randomNumber;
        roundInfo.randomNumber = randomNumber = uint256(
            keccak256(secretsInRevealOrder)
        );
        RequestInfo storage requestInfo = s_requestInfo[round];
        bool success = _call(
            requestInfo.consumer,
            abi.encodeWithSelector(
                DRBConsumerBase.rawFulfillRandomWords.selector,
                round,
                randomNumber
            ),
            requestInfo.callbackGasLimit
        );
        roundInfo.fulfillSucceeded = success;
        address[]
            storage activatedOperatorsAtRound = s_activatedOperatorsAtRound[
                round
            ];
        uint256 cost = requestInfo.cost;
        uint256 activatedOperatorsLength = activatedOperatorsAtRound.length;
        uint256 costWithReward = cost + (cost / (activatedOperatorsLength - 1));
        uint256 activationThreshold = s_activationThreshold;

        for (
            uint256 i = 1;
            i < activatedOperatorsLength;
            i = unchecked_inc(i)
        ) {
            address operator = activatedOperatorsAtRound[i];
            _checkAndActivateIfNotForceDeactivated(
                s_activatedOperatorOrder[operator],
                s_depositAmount[operator] += costWithReward,
                activationThreshold,
                operator
            );
        }
        emit RandomNumberGenerated(round, randomNumber);
    }

    function createMerkleRootExternal(
        bytes32[] memory leaves
    ) external pure returns (bytes32) {
        uint256 leavesLen = leaves.length;
        uint256 hashCount = leavesLen - 1;
        bytes32[] memory hashes = new bytes32[](hashCount);
        uint256 leafPos = 0;
        uint256 hashPos = 0;
        for (uint256 i = 0; i < hashCount; i = unchecked_inc(i)) {
            bytes32 a = leafPos < leavesLen
                ? leaves[leafPos++]
                : hashes[hashPos++];
            bytes32 b = leafPos < leavesLen
                ? leaves[leafPos++]
                : hashes[hashPos++];
            hashes[i] = _efficientKeccak256(a, b);
        }
        return hashes[hashCount - 1];
    }

    function _efficientKeccak256(
        bytes32 a,
        bytes32 b
    ) private pure returns (bytes32 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function createMerkleRoot(
        bytes32[] memory leaves
    ) private pure returns (bytes32) {
        uint256 leavesLen = leaves.length;
        uint256 hashCount = leavesLen - 1;
        bytes32[] memory hashes = new bytes32[](hashCount);
        uint256 leafPos = 0;
        uint256 hashPos = 0;
        for (uint256 i = 0; i < hashCount; i = unchecked_inc(i)) {
            bytes32 a = leafPos < leavesLen
                ? leaves[leafPos++]
                : hashes[hashPos++];
            bytes32 b = leafPos < leavesLen
                ? leaves[leafPos++]
                : hashes[hashPos++];
            hashes[i] = _efficientKeccak256(a, b);
        }
        return hashes[hashCount - 1];
    }

    function unchecked_inc(uint256 i) private pure returns (uint256) {
        unchecked {
            return i + 1;
        }
    }

    /// ** deposit and withdraw
    function deposit() external payable nonReentrant {
        _deposit();
    }

    function activate() external nonReentrant {
        require(
            s_depositAmount[msg.sender] >= s_activationThreshold,
            InsufficientDeposit()
        );
        if (s_forceDeactivated[msg.sender])
            s_forceDeactivated[msg.sender] = false;
        _activate(msg.sender);
    }

    function deactivate() external nonReentrant {
        uint256 activatedOperatorIndex = s_activatedOperatorOrder[msg.sender];
        require(activatedOperatorIndex != 0, OperatorNotActivated());
        require(
            s_forceDeactivated[msg.sender] == false,
            AlreadyForceDeactivated()
        );
        s_forceDeactivated[msg.sender] = true;
        _deactivate(activatedOperatorIndex, msg.sender);
    }

    function depositAndActivate() external payable nonReentrant {
        _deposit();
        _activate(msg.sender);
    }

    function withdraw(uint256 amount) external nonReentrant {
        s_depositAmount[msg.sender] -= amount;
        uint256 activatedOperatorIndex = s_activatedOperatorOrder[msg.sender];
        if (
            activatedOperatorIndex != 0 &&
            s_depositAmount[msg.sender] < s_activationThreshold
        ) _deactivate(activatedOperatorIndex, msg.sender);
        payable(msg.sender).transfer(amount);
    }

    /// *** operator internal functions
    function _activate(address operator) private {
        require(s_activatedOperatorOrder[operator] == 0, AlreadyActivated());
        uint256 activatedOperatorLength = s_activatedOperators.length;
        require(
            activatedOperatorLength <= MAX_ACTIVATED_OPERATORS,
            ActivatedOperatorsLimitReached()
        );
        s_activatedOperatorOrder[operator] = activatedOperatorLength;
        s_activatedOperators.push(operator);
        emit Activated(operator);
    }

    function _deposit() private {
        uint256 totalAmount = s_depositAmount[msg.sender] + msg.value;
        require(totalAmount >= s_activationThreshold, InsufficientAmount());
        s_depositAmount[msg.sender] = totalAmount;
    }

    function _deactivate(
        uint256 activatedOperatorIndex,
        address operator
    ) private {
        address lastOperator = s_activatedOperators[
            s_activatedOperators.length - 1
        ];
        s_activatedOperators[activatedOperatorIndex] = lastOperator;
        s_activatedOperators.pop();
        s_activatedOperatorOrder[lastOperator] = activatedOperatorIndex;
        delete s_activatedOperatorOrder[operator];
        emit DeActivated(operator);
    }

    function _checkAndActivateIfNotForceDeactivated(
        uint256 activatedOperatorIndex,
        uint256 updatedDepositAmount,
        uint256 minDepositForThisRound,
        address operator
    ) private {
        if (
            activatedOperatorIndex == 0 &&
            updatedDepositAmount >= minDepositForThisRound &&
            !s_forceDeactivated[operator]
        ) {
            _activate(operator);
        }
    }

    function _call(
        address target,
        bytes memory data,
        uint256 callbackGasLimit
    ) private returns (bool success) {
        assembly {
            let g := gas()
            // Compute g -= GAS_FOR_CALL_EXACT_CHECK and check for underflow
            // The gas actually passed to the callee is min(gasAmount, 63//64*gas available)
            // We want to ensure that we revert if gasAmount > 63//64*gas available
            // as we do not want to provide them with less, however that check itself costs
            // gas. GAS_FOR_CALL_EXACT_CHECK ensures we have at least enough gas to be able to revert
            // if gasAmount > 63//64*gas available.
            if lt(g, GAS_FOR_CALL_EXACT_CHECK) {
                revert(0, 0)
            }
            g := sub(g, GAS_FOR_CALL_EXACT_CHECK)
            // if g - g//64 <= gas
            // we subtract g//64 because of EIP-150
            g := sub(g, div(g, 64))
            if iszero(gt(sub(g, div(g, 64)), callbackGasLimit)) {
                revert(0, 0)
            }
            // solidity calls check that a contract actually exists at the destination, so we do the same
            if iszero(extcodesize(target)) {
                revert(0, 0)
            }
            // call and return whether we succeeded. ignore return data
            // call(gas, addr, value, argsOffset,argsLength,retOffset,retLength)
            success := call(
                callbackGasLimit,
                target,
                0,
                add(data, 0x20),
                mload(data),
                0,
                0
            )
        }
        return success;
    }
}
