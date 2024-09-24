// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DRBConsumerBase} from "./DRBConsumerBase.sol";

/**
 * @title RareTitle
 * @notice This contract implements a game where players can earn points by
 *         claiming titles on a board. The game uses DRBCoordinator for random number
 *         generation and rewards players with tokens.
 */
contract RareTitle is DRBConsumerBase, ReentrancyGuard, Ownable {
    enum RequestStatus {
        NOTREQUESTED,
        REQUESTED,
        FULFILLED,
        REFUNDED
    }
    // Struct to store player information
    struct User {
        int16 totalPoints;
        uint8 totalTurns;
        uint256[] requestIds;
    }

    struct RequestInfo {
        address player;
        uint256 randomNumber;
        RequestStatus status;
    }

    mapping(uint256 requestId => RequestInfo requestInfo) public s_requests;

    // Constants
    uint8 public constant BOARD_SIZE = 100;
    uint8 public constant MAX_NO_OF_TURNS = 10;
    uint32 public constant CALLBACK_GAS_LIMIT = 120000; // Depends on the number of requested values that you request

    // Storage Variables
    IERC20 public tonToken;
    bool public rewardClaimed;
    uint256 public reward; // Total TON reward set by the owner
    int16 private winnerPoint = -100;

    uint256 private gameExpiry; // Time at which the game expires
    address[] private winners;
    uint256 private refundRequestId;
    mapping(address => User) private playerInfo; // Mapping of each user position

    // Events
    event RequestFulfilled(uint256 requestId, uint256 randomWord);
    event GameExpiryUpdated(uint256 gameExpiry);
    event FundsWithdrawn(uint256 amount);
    event RewardClaimed(address[] winners, uint256 reward);

    // Errors
    error InvalidGameExpiry(uint256 newGameExpiry);
    error UserTurnsExhausted(address user);
    error RequestNotFound(uint256 requestId);
    error InsufficientBalance(uint256 required, uint256 actual);
    error GameNotActive();
    error GameNotExpired();
    error NoAmountToWithdraw();
    error RewardAlreadyClaimed();
    error InvalidAddress();
    error InvalidReward();

    // Modifiers

    /**
     * @dev Modifier to check if the game is active.
     */
    modifier gameActive() {
        if (block.timestamp > gameExpiry) {
            revert GameNotActive();
        }
        _;
    }

    /**
     * @dev Modifier to make sure game has expired.
     */
    modifier gameExpired() {
        if (block.timestamp <= gameExpiry) {
            revert GameNotExpired();
        }
        _;
    }

    /**
     * @dev Initializes the game board and sets initial values.
     */
    constructor(
        address _rngCoordinator,
        uint256 _gameExpiry,
        IERC20 _ton,
        uint256 _reward
    ) DRBConsumerBase(_rngCoordinator) Ownable(msg.sender) {
        require(_gameExpiry != 0, InvalidGameExpiry(_gameExpiry));
        gameExpiry = _gameExpiry;

        require(address(_ton) != address(0), InvalidAddress());
        tonToken = _ton;

        require(_reward != 0, InvalidReward());
        reward = _reward;
    }

    receive() external payable override {
        if (msg.sender == address(i_drbCoordinator)) {
            uint256 requestId = refundRequestId;
            RequestInfo storage request = s_requests[requestId];
            request.status = RequestStatus.REFUNDED;
            address player = request.player;
            // refund
            unchecked {
                playerInfo[player].totalTurns--;
            }
            payable(player).transfer(msg.value);
            refundRequestId = 0;
        }
    }

    function viewTotalPoints() public view returns (int16 totalPoints) {
        User memory user = playerInfo[msg.sender];
        totalPoints = user.totalPoints;
    }

    function viewRemainingTurns() public view returns (uint256 remainingTurns) {
        User memory user = playerInfo[msg.sender];
        remainingTurns = MAX_NO_OF_TURNS - user.totalTurns;
    }

    function viewEventInfos()
        public
        view
        returns (
            uint256[] memory requestIds,
            uint256[] memory randomNumbers,
            uint8[] memory requestStatus,
            int16 totalPoints,
            uint8 totalTurns,
            int16 _winnerPoint,
            uint256 winnerLength,
            uint256 _gameExpiry
        )
    {
        requestIds = playerInfo[msg.sender].requestIds;
        uint256 length = requestIds.length;
        requestStatus = new uint8[](length);
        randomNumbers = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            RequestInfo memory request = s_requests[requestIds[i]];
            requestStatus[i] = uint8(request.status);
            randomNumbers[i] = request.randomNumber;
        }
        totalPoints = playerInfo[msg.sender].totalPoints;
        totalTurns = playerInfo[msg.sender].totalTurns;
        _winnerPoint = winnerPoint;
        winnerLength = winners.length;
        _gameExpiry = gameExpiry;
    }

    /**
     * @notice Allows the player to take a turn in the game, requesting a random number.
     * @dev Ensures that the game is active and that the player hasn't exhausted their allowed number of turns.
     *      Increments the player's total turns and makes a request for a random number.
     *      The request ID is stored and associated with the player for later processing.
     * @notice Reverts with `UserTurnsExhausted` if the player has exhausted their allowed turns.
     */
    function play() external payable gameActive returns (uint256 requestId) {
        User storage user = playerInfo[msg.sender];
        if (user.totalTurns == MAX_NO_OF_TURNS) {
            revert UserTurnsExhausted(msg.sender);
        }
        unchecked {
            ++user.totalTurns;
        }
        requestId = _requestRandomNumber(CALLBACK_GAS_LIMIT);
        RequestInfo storage request = s_requests[requestId];
        request.status = RequestStatus.REQUESTED;
        request.player = msg.sender;
        user.requestIds.push(requestId);
    }

    /**
     * @notice Allows the winner to claim their prize after the game has expired.
     * @dev This function checks if the caller is the winner, ensures the reward has not already
     *      been claimed, and verifies the contract has enough balance to transfer the reward.
     *      Emits a {RewardClaimed} event upon successful transfer of the reward.
     */
    function claimPrize() external gameExpired onlyOwner {
        if (rewardClaimed) {
            revert RewardAlreadyClaimed();
        }

        uint256 balance = tonToken.balanceOf(address(this));

        if (balance < reward) {
            revert InsufficientBalance(balance, reward);
        }
        uint256 distribution = reward / winners.length;
        for (uint256 i = 0; i < winners.length; i++) {
            tonToken.transfer(winners[i], distribution);
        }
        rewardClaimed = true;
        emit RewardClaimed(winners, reward);
    }

    /**
     * @dev Updates the game Expiry.
     * @param _newGameExpiry The new game Expiry in seconds.
     * @notice Only the contract owner can call this function.
     * @dev Reverts if the new Expiry is the same as the current one.
     */
    function updateGameExpiry(
        uint256 _newGameExpiry
    ) external gameActive onlyOwner {
        if (_newGameExpiry == gameExpiry || _newGameExpiry == 0) {
            revert InvalidGameExpiry(_newGameExpiry);
        }

        gameExpiry = _newGameExpiry;
        emit GameExpiryUpdated(_newGameExpiry);
    }

    /**
     * @notice Withdraws all Ether from the contract to the owner.
     * @dev This function is restricted to the contract owner via the `onlyOwner` modifier.
     * @dev It reverts with a `NoEtherToWithdraw` error if the contract balance is zero.
     * @dev Transfers the entire balance to the owner and emits a `FundsWithdrawn` event.
     */
    function withdrawEth() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) {
            revert NoAmountToWithdraw();
        }

        payable(owner()).transfer(balance);
        emit FundsWithdrawn(balance);
    }

    /**
     * @notice Withdraws all TON from the contract to the owner.
     * @dev This function is restricted to the contract owner via the `onlyOwner` modifier.
     * @dev It reverts with a `NoAmountToWithdraw` error if the contract balance is zero.
     * @dev Transfers the entire balance to the owner and emits a `FundsWithdrawn` event.
     */
    function withdrawTon() external onlyOwner {
        uint256 balance = tonToken.balanceOf(address(this));
        if (balance == 0) {
            revert NoAmountToWithdraw();
        }

        tonToken.transfer(owner(), balance);
        emit FundsWithdrawn(balance);
    }

    /**
     * @notice Internal function to fulfill the randomness request with the provided random word.
     * @dev This function is called by the DRBCoordinator.
     *      It ensures that the request is valid, assigns the random word to the request, calculates
     *      the board position, and updates the player's total points. It also updates the winner if the
     *      current player exceeds the current winner's total points.
     * @param _requestId The ID of the randomness request.
     * @param _randomWord The random number provided by DRBCoordinator.
     */
    function fulfillRandomWords(
        uint256 _requestId,
        uint256 _randomWord
    ) internal override {
        if (s_requests[_requestId].status != RequestStatus.REQUESTED) {
            revert RequestNotFound(_requestId);
        }
        RequestInfo storage request = s_requests[_requestId];
        request.status = RequestStatus.FULFILLED;
        request.randomNumber = _randomWord;
        address _player = request.player;
        int16 addPoint;
        uint256 modBoardSize = _randomWord % BOARD_SIZE;
        if (modBoardSize > 53) addPoint = -5;
        else if (modBoardSize > 13) addPoint = 10;
        else if (modBoardSize > 3) addPoint = 20;
        else if (modBoardSize > 0) addPoint = 30;
        else addPoint = 100;
        int16 myTotalPoint;
        unchecked {
            myTotalPoint = playerInfo[_player].totalPoints += addPoint;
        }
        if (myTotalPoint > winnerPoint) {
            winnerPoint = myTotalPoint;
            delete winners;
            winners.push(_player);
        } else if (myTotalPoint == winnerPoint) {
            winners.push(_player);
        }
    }

    function getRefund(uint256 requestId) external override nonReentrant {
        refundRequestId = requestId;
        i_drbCoordinator.getRefund(requestId);
    }

    /**
     * @dev Initializes the game board by populating it with a predefined set of `Title` objects.
     *      The function fills the `gameBoard` with `points` from the available titles, ensuring
     *      that the titles are placed according to their maximum count.
     *
     *      The titles are:
     *      - Title 1: 100 points, total count of 1
     *      - Title 2: 30 points, total count of 3
     *      - Title 3: 20 points, total count of 10
     *      - Title 4: 10 points, total count of 40
     *      - Title 5: -5 points, total count of 46
     *
     *      Once the `total` for a particular title is reached, the function proceeds to the next title.
     *
     * @notice This function must be called internally to set up the initial state of the game board.
     */
}
