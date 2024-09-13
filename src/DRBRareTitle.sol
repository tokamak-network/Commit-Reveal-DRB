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
    // Struct to store player information
    struct User {
        int16 totalPoints;
        uint8 totalTurns;
    }

    struct RequestStatus {
        bool requested; // whether the request has been made
        bool fulfilled; // whether the request has been successfully fulfilled
        address player;
        uint256 randomNumber;
    }

    struct Title {
        int8 points;
        uint8 maxCount;
    }

    mapping(uint256 requestId => RequestStatus requestStatus) public s_requests;

    // Constants
    uint8 public constant BOARD_SIZE = 100;
    uint8 public constant MAX_NO_OF_TURNS = 10;
    uint32 private constant CALLBACK_GAS_LIMIT = 50000; // Depends on the number of requested values that you request

    // Storage Variables
    IERC20 public tonToken;
    bool public rewardClaimed;
    uint256 public gameExpiry; // Time at which the game expires
    uint256 public reward; // Total TON reward set by the owner
    uint256[] public requestIds; // past requests Id.
    Title[] public titles;

    address private winner;
    int8[BOARD_SIZE] private gameBoard;
    mapping(address => User) private playerInfo; // Mapping of each user position

    // Events
    event RequestFulfilled(uint256 requestId, uint256 randomWord);
    event GameExpiryUpdated(uint256 gameExpiry);
    event FundsWithdrawn(uint256 amount);
    event RewardClaimed(address winner, uint256 reward);

    // Errors
    error InvalidGameExpiry(uint256 newGameExpiry);
    error UserTurnsExhausted(address user);
    error RequestNotFound(uint256 requestId);
    error CallerIsNotWinner(address caller);
    error InsufficientBalance(uint256 required, uint256 actual);
    error GameNotActive();
    error GameNotExpired();
    error NoEtherToWithdraw();
    error RewardAlreadyClaimed();

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
        IERC20 _ton,
        uint256 _reward
    ) DRBConsumerBase(_rngCoordinator) Ownable(msg.sender) {
        _initializeBoard();
        tonToken = _ton;
        reward = _reward;
    }

    /**
     * @notice Allows the player to take a turn in the game, requesting a random number.
     * @dev Ensures that the game is active and that the player hasn't exhausted their allowed number of turns.
     *      Increments the player's total turns and makes a request for a random number.
     *      The request ID is stored and associated with the player for later processing.
     * @notice Reverts with `UserTurnsExhausted` if the player has exhausted their allowed turns.
     */
    function play() external payable gameActive {
        User storage user = playerInfo[msg.sender];
        if (user.totalTurns == MAX_NO_OF_TURNS) {
            revert UserTurnsExhausted(msg.sender);
        }
        user.totalTurns++;

        uint256 requestId = _requestRandomNumber(CALLBACK_GAS_LIMIT);
        RequestStatus storage request = s_requests[requestId];
        request.requested = true;
        request.player = msg.sender;
        requestIds.push(requestId);
    }

    /**
     * @notice Allows the winner to claim their prize after the game has expired.
     * @dev This function checks if the caller is the winner, ensures the reward has not already
     *      been claimed, and verifies the contract has enough balance to transfer the reward.
     *      Emits a {RewardClaimed} event upon successful transfer of the reward.
     */
    function claimPrize() external gameExpired {
        if (msg.sender != winner) {
            revert CallerIsNotWinner(msg.sender);
        }

        if (rewardClaimed) {
            revert RewardAlreadyClaimed();
        }

        uint256 balance = tonToken.balanceOf(address(this));

        if (balance < reward) {
            revert InsufficientBalance(balance, reward);
        }

        tonToken.transfer(msg.sender, reward);
        emit RewardClaimed(msg.sender, reward);
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
            revert NoEtherToWithdraw();
        }

        payable(owner()).transfer(balance);
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
        if (!s_requests[_requestId].requested) {
            revert RequestNotFound(_requestId);
        }
        RequestStatus storage request = s_requests[_requestId];
        request.fulfilled = true;
        request.randomNumber = _randomWord;
        uint256 boardPosition = _randomWord % BOARD_SIZE;
        address _player = request.player;
        User storage player = playerInfo[_player];
        player.totalPoints += gameBoard[boardPosition];

        if (
            winner == address(0) ||
            playerInfo[winner].totalPoints < player.totalPoints
        ) {
            winner = _player;
        }

        emit RequestFulfilled(_requestId, _randomWord);
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
    function _initializeBoard() internal {
        titles.push(Title(int8(100), 1));
        titles.push(Title(int8(30), 3));
        titles.push(Title(int8(20), 10));
        titles.push(Title(int8(10), 40));
        titles.push(Title(int8(-5), 46));
        uint256 j;

        // Randomly fill the board
        for (uint256 i = 0; i < BOARD_SIZE; ++i) {
            Title memory title = titles[j];

            // Check if the title can be placed
            if (title.maxCount == 0) {
                ++j;
                title = titles[j];
            }
            gameBoard[i] = title.points;
            title.maxCount--;
            titles[j] = title;
        }
    }
}
