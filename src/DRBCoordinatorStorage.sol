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
    mapping(uint256 round => address[] activatedOperators) internal s_activatedOperatorsAtRound;
    mapping(uint256 round => mapping(address operator => uint256)) internal s_activatedOperatorOrderAtRound;
    mapping(uint256 round => RequestInfo requestInfo) internal s_requestInfo;
    mapping(uint256 round => RoundInfo roundInfo) internal s_roundInfo;
    mapping(uint256 round => bytes32[] commits) internal s_commits;
    mapping(uint256 round => bytes32[] reveals) internal s_reveals;
    mapping(address operator => bool isForceDeactivated) internal s_forceDeactivated;
    mapping(address operator => uint256 depositAmount) internal s_depositAmount;
    mapping(address operator => uint256) internal s_activatedOperatorOrder;
    mapping(uint256 round => mapping(address operator => uint256)) internal s_commitOrder;
    mapping(uint256 round => mapping(address operator => uint256)) internal s_revealOrder;
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

    /// *** Events ***
    event RandomNumberRequested(uint256 round, address[] activatedOperators);
    event Commit(address operator, uint256 round);
    event Reveal(address operator, uint256 round);
    event Refund(uint256 round);
    event Activated(address operator);
    event DeActivated(address operator);
    event ActivationThresholdUpdated(uint256 activationThreshold);
    event FlatFeeUpdated(uint256 flatFee);
    event CompensationAmountUpdated(uint256 compensationAmount);
    event PremiumPercentageUpdated(uint256 premiumPercentage);

    /// *** Getter Functions ***

    /**
     * @notice Returns the maximum wait time, commit duration, and reveal duration.
     * @return maxWait The maximum waiting time allowed.
     * @return commitDuration The duration of the commit phase.
     * @return revealDuration The duration of the reveal phase.
     */
    function getDurations() external pure returns (uint256 maxWait, uint256 commitDuration, uint256 revealDuration) {
        return (MAX_WAIT, COMMIT_DURATION, REVEAL_DURATION);
    }

    /**
     * @notice Returns the maximum number of activated operators.
     * @return The maximum number of activated operators as a `uint256`.
     */
    function getMaxActivatedOperators() external pure returns (uint256) {
        return MAX_ACTIVATED_OPERATORS;
    }

    /**
     * @notice Retrieves the current compensation amount stored in the contract.
     * @return The current compensation amount as a uint256.
     */
    function getCompensateAmount() external view returns (uint256) {
        return s_compensateAmount;
    }

    /**
     * @notice Retrieves the deposit amount for a given operator.
     * @param operator The address of the operator whose deposit amount is being queried.
     * @return The amount of the deposit for the specified operator.
     */
    function getDepositAmount(address operator) external view returns (uint256) {
        return s_depositAmount[operator];
    }

    /**
     * @notice Retrieves the index of the activated operator.
     * @param operator The address of the operator whose index is being queried.
     * @return The index of the activated operator associated with the given address.
     */
    function getActivatedOperatorIndex(address operator) external view returns (uint256) {
        return s_activatedOperatorOrder[operator];
    }

    /**
     * @notice Retrieves the list of currently activated operator addresses.
     * @return address[] memory An array of addresses of activated operators.
     */
    function getActivatedOperators() external view returns (address[] memory) {
        return s_activatedOperators;
    }

    /**
     * @notice Returns the number of activated operators.
     * @return The number of activated operators as a uint256.
     */
    function getActivatedOperatorsLength() external view returns (uint256) {
        return s_activatedOperators.length - 1;
    }

    /**
     * @notice Retrieves the minimum deposit amount required for activation,
     *         which is the activation threshold.
     * @return The minimum deposit amount as a uint256.
     */
    function getMinDeposit() external view returns (uint256) {
        return s_activationThreshold;
    }

    /**
     * @notice Retrieves the information for a specific request based on the round number.
     * @param round The round number for which to retrieve the request information.
     * @return The RequestInfo struct containing details about the specified request.
     */
    function getRequestInfo(uint256 round) external view returns (RequestInfo memory) {
        return s_requestInfo[round];
    }

    /**
     * @notice Retrieves the list of activated operators for a specific round.
     * @param round The round number to query for activated operators.
     * @return An array of addresses representing the activated operators in the specified round.
     */
    function getActivatedOperatorsAtRound(uint256 round) external view returns (address[] memory) {
        return s_activatedOperatorsAtRound[round];
    }

    /**
     * @notice Returns the number of activated operators at a specific round.
     * @param round The round number for which the number of activated operators is requested.
     * @return The number of activated operators at the specified round.
     */
    function getActivatedOperatorsLengthAtRound(uint256 round) external view returns (uint256) {
        return s_activatedOperatorsAtRound[round].length - 1;
    }

    /**
     * @notice Retrieves information about a specific round.
     * @param round The round number for which information is being requested.
     * @return The information related to the specified round as a `RoundInfo` struct.
     */
    function getRoundInfo(uint256 round) external view returns (RoundInfo memory) {
        return s_roundInfo[round];
    }

    /**
     * @notice Retrieves the commits for a specific round.
     * @param round The round number for which commits are requested.
     * @return An array of bytes32 values representing the commits for the specified round.
     */
    function getCommits(uint256 round) external view returns (bytes32[] memory) {
        return s_commits[round];
    }

    /**
     * @notice Returns the number of commits for a specific round.
     * @param round The round for which the length of commits is requested.
     * @return The number of commits in the specified round.
     */
    function getCommitsLength(uint256 round) external view returns (uint256) {
        return s_commits[round].length;
    }

    /**
     * @notice Retrieves the commit order for a given round and operator.
     * @param round The round number for which the commit order is being fetched.
     * @param operator The address of the operator whose commit order is being queried.
     * @return The commit order of the specified operator for the given round.
     */
    function getCommitOrder(uint256 round, address operator) external view returns (uint256) {
        return s_commitOrder[round][operator];
    }

    /**
     * @notice Retrieves the list of reveal hashes for a specific round.
     * @param round The round number for which the reveal hashes are being requested.
     * @return An array of bytes32 representing the reveal hashes for the specified round.
     */
    function getReveals(uint256 round) external view returns (bytes32[] memory) {
        return s_reveals[round];
    }

    /**
     * @notice Retrieves the reveal order for a given round and operator.
     * @param round The round number for which the reveal order is being requested.
     * @param operator The address of the operator whose reveal order is being retrieved.
     * @return The reveal order of the operator for the specified round.
     */
    function getRevealOrder(uint256 round, address operator) external view returns (uint256) {
        return s_revealOrder[round][operator];
    }

    /**
     * @notice Retrieves the length of the reveals array for a specific round.
     * @param round The round number for which the reveals length is being requested.
     * @return The number of reveals in the specified round.
     */
    function getRevealsLength(uint256 round) external view returns (uint256) {
        return s_reveals[round].length;
    }
}
