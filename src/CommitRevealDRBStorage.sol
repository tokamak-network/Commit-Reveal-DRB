// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract CommitRevealDRBStorage {
    /// *** Type Declarations ***
    struct RequestInfo {
        address consumer;
        uint256 requestedTime;
        uint256 cost;
        uint256 callbackGasLimit;
    }

    struct RoundInfo {
        bytes32 merkleRoot;
        uint256 randomNumber;
        bool fulfillSucceeded;
    }

    /// *** Erros ***
    error InsufficientDeposit();
    error InsufficientAmount();
    error AlreadyForceDeactivated();
    error OperatorNotActivated();
    error AlreadyActivated();
    error ActivatedOperatorsLimitReached();
    error ExceedCallbackGasLimit();
    error NotEnoughActivatedOperators();
    error NotActivatedOperatorForThisRound();
    error RevealNotInAscendingOrder();
    error MerkleVerificationFailed();
    error InvalidSignature(address operator);

    /// *** Events ***
    event RandomNumberRequested(uint256 round, address[] activatedOperators);
    event RandomNumberGenerated(uint256 round, uint256 randomNumber);
    event Activated(address operator);
    event DeActivated(address operator);

    /// *** State variables ***
    // ** constant
    uint256 internal constant MAX_ACTIVATED_OPERATORS = 7;
    uint256 internal constant MAX_CALLBACK_GAS_LIMIT = 2500000;
    uint256 internal constant MERKLEROOTSUB_RANDOMNUMGENERATE_GASUSED = 100000;
    uint256 internal constant MERKLEROOTSUB_CALLDATA_BYTES_SIZE = 214;
    uint256 internal constant RANDOMNUMGENERATE_CALLDATA_BYTES_SIZE = 278;
    uint256 internal constant GAS_FOR_CALL_EXACT_CHECK = 5_000;

    // ** public
    mapping(uint256 round => RoundInfo roundInfo) public s_roundInfo;
    mapping(uint256 round => RequestInfo requestInfo) public s_requestInfo;
    uint256 public s_activationThreshold;
    mapping(uint256 round => address[] activatedOperators)
        public s_activatedOperatorsAtRound;
    mapping(address operator => uint256 depositAmount) public s_depositAmount;
    mapping(address operator => uint256) public s_activatedOperatorOrder;

    // ** internal
    address[] internal s_activatedOperators;
    uint256 internal s_nextRound;
    uint256 internal s_premiumPercentage;
    uint256 internal s_flatFee;
    mapping(address operator => bool isForceDeactivated)
        internal s_forceDeactivated;
    mapping(uint256 round => mapping(address operator => uint256))
        internal s_activatedOperatorOrderAtRound;

    // ** getter
    // s_activatedOperators
    function getActivatedOperators() external view returns (address[] memory) {
        return s_activatedOperators;
    }
}
