// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract DRBCoordinatorStorage {
    /// **** Type Declarations ****
    struct RequestInfo {
        address consumer;
        uint256 requestedTime;
        uint256 cost;
        uint256 callbackGasLimit;
        uint256 minDepositForOperator;
        uint256 requestAndRefundCost;
    }

    struct RoundInfo {
        uint256 commitEndTime;
        uint256 randomNumber;
        bool fulfillSucceeded;
    }

    /// *** State variables ***
    mapping(uint256 round => address[] activatedOperators)
        internal s_activatedOperatorsAtRound;
    mapping(uint256 round => mapping(address operator => uint256))
        internal s_activatedOperatorOrderAtRound;
    mapping(uint256 round => RequestInfo requestInfo) internal s_requestInfo;
    mapping(uint256 round => RoundInfo roundInfo) internal s_roundInfo;
    mapping(uint256 round => bytes32[] commits) internal s_commits;
    mapping(uint256 round => bytes32[] reveals) internal s_reveals;

    mapping(address operator => bool isForceDeactivated)
        internal s_forceDeactivated;
    mapping(address operator => uint256 depositAmount) internal s_depositAmount;
    mapping(address operator => uint256) internal s_activatedOperatorOrder;
    mapping(uint256 round => mapping(address operator => uint256))
        internal s_commitOrder;
    mapping(uint256 round => mapping(address operator => uint256))
        internal s_revealOrder;
    address[] internal s_activatedOperators;
    uint256 internal s_compensateAmount;
    uint256 internal s_currentRound;
    uint256 internal s_nextRound;
    uint256 internal s_premiumPercentage;
    uint256 internal s_flatFee;
    uint256 internal s_activationThreshold;

    /// *** Constants ***
    uint256 internal constant MAX_WAIT = 10 minutes;
    uint256 internal constant COMMIT_DURATION = 5 minutes;
    uint256 internal constant REVEAL_DURATION = 10 minutes;
    uint256 internal constant TWOCOMMIT_TWOREVEAL_GASUSED = 511753;
    uint256 internal constant TWOCOMMIT_TWOREVEAL_CALLDATA_BYTES_SIZE = 556;
    uint256 internal constant ONECOMMIT_ONEREVEAL_GASUSED = 255877;
    uint256 internal constant ONECOMMIT_ONEREVEAL_CALLDATA_BYTES_SIZE = 278;
    uint256 internal constant MAX_REQUEST_REFUND_GASUSED = 702530;
    uint256 internal constant REQUEST_REFUND_CALLDATA_BYTES_SIZE = 214;
    uint256 internal constant MAX_CALLBACK_GAS_LIMIT = 2500000;
    /// @dev 5k is plenty for an EXTCODESIZE call (2600) + warm CALL (100) and some arithmetic operations
    uint256 internal constant GAS_FOR_CALL_EXACT_CHECK = 5_000;
    uint256 internal constant MAX_ACTIVATED_OPERATORS = 7;

    /// *** Errors ***
    error InsufficientAmount();
    error InsufficientDeposit();
    error NotEnoughActivatedOperators();
    error AlreadyActivated();
    error AlreadyForceDeactivated();
    error NotActivatedOperator();
    error NotCommitted();
    error WasNotActivated();
    error CommitPhaseOver();
    error NotRevealPhase();
    error AlreadyCommitted();
    error RevealValueMismatch();
    error AlreadyRevealed();
    error NotSlashingCondition();
    error NotRefundable();
    error NotConsumer();
    error ACTIVATED_OPERATORS_LIMIT_REACHED();
    error ExceedCallbackGasLimit();
    error FailedToSendEther();

    /// *** Events ***
    event RandomNumberRequested(uint256 round, address[] activatedOperators);
    event Commit(address operator, uint256 round);
    event Reveal(address operator, uint256 round);
    event Refund(uint256 round);
    event Activated(address operator);
    event DeActivated(address operator);

    /// *** Getter Functions ***
    function getDurations()
        external
        pure
        returns (
            uint256 maxWait,
            uint256 commitDuration,
            uint256 revealDuration
        )
    {
        return (MAX_WAIT, COMMIT_DURATION, REVEAL_DURATION);
    }

    /// *** MAX_ACTIVATED_OPERATORS
    function getMaxActivatedOperators() external pure returns (uint256) {
        return MAX_ACTIVATED_OPERATORS;
    }

    /// ** s_compensateAmount
    function getCompensateAmount() external view returns (uint256) {
        return s_compensateAmount;
    }

    /// ** s_depositAmount
    function getDepositAmount(
        address operator
    ) external view returns (uint256) {
        return s_depositAmount[operator];
    }

    /// ** s_activatedOperatorOrder
    function getActivatedOperatorIndex(
        address operator
    ) external view returns (uint256) {
        return s_activatedOperatorOrder[operator];
    }

    /// ** s_activatedOperators
    function getActivatedOperators() external view returns (address[] memory) {
        return s_activatedOperators;
    }

    function getActivatedOperatorsLength() external view returns (uint256) {
        return s_activatedOperators.length - 1;
    }

    /// ** s_activationThreshold
    function getMinDeposit() external view returns (uint256) {
        return s_activationThreshold;
    }

    /// ** s_requestInfo
    function getRequestInfo(
        uint256 round
    ) external view returns (RequestInfo memory) {
        return s_requestInfo[round];
    }

    /// ** s_activatedOperatorsAtRound
    function getActivatedOperatorsAtRound(
        uint256 round
    ) external view returns (address[] memory) {
        return s_activatedOperatorsAtRound[round];
    }

    function getActivatedOperatorsLengthAtRound(
        uint256 round
    ) external view returns (uint256) {
        return s_activatedOperatorsAtRound[round].length - 1;
    }

    /// ** s_roundInfo
    function getRoundInfo(
        uint256 round
    ) external view returns (RoundInfo memory) {
        return s_roundInfo[round];
    }

    /// ** s_commits
    function getCommits(
        uint256 round
    ) external view returns (bytes32[] memory) {
        return s_commits[round];
    }

    function getCommitsLength(uint256 round) external view returns (uint256) {
        return s_commits[round].length;
    }

    /// ** s_commitOrder
    function getCommitOrder(
        uint256 round,
        address operator
    ) external view returns (uint256) {
        return s_commitOrder[round][operator];
    }

    /// ** s_reveals
    function getReveals(
        uint256 round
    ) external view returns (bytes32[] memory) {
        return s_reveals[round];
    }

    /// ** s_revealOrder
    function getRevealOrder(
        uint256 round,
        address operator
    ) external view returns (uint256) {
        return s_revealOrder[round][operator];
    }

    function getRevealsLength(uint256 round) external view returns (uint256) {
        return s_reveals[round].length;
    }
}
