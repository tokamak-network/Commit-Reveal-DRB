// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DRBConsumerBase} from "./DRBConsumerBase.sol";

contract RareTitle is DRBConsumerBase, Ownable {
    // Struct to store player information
    struct User {
        int256 totalPoints;
        bytes16 chosenSquares;
        uint8 totalTurns;
        bool validMember;
    }

    struct RequestStatus {
        bool requested; // whether the request has been made
        bool fulfilled; // whether the request has been successfully fulfilled
        address player;
        uint256 randomNumber;
    }

    struct Title {
        uint8 id;
        int8 points;
        uint8 maxCount;
    }

    mapping(uint256 => RequestStatus)
        public s_requests; /* requestId --> requestStatus */

    // Constants
    uint8 public constant BOARD_SIZE = 100;
    uint32 private constant CALLBACK_GAS_LIMIT = 50000; // Depends on the number of requested values that you request
    uint8 public constant MAX_NO_OF_TURNS = 10;
    uint32 private constant NUM_OF_RANDOM_WORDS = 1;

    // Storage Variables
    uint256 public gameDuration; // Duration after which the game expires
    uint256 public participationFee;
    uint256 public totalBalance; // Total ETH received in the game
    address public currentPlayer;
    bool public isGameActive;
    address private winner;
    uint256[] public requestIds; // past requests Id.
    int8[BOARD_SIZE] private gameBoard;
    Title[] public titles;
    mapping(address => User) private playerInfo; // Mapping of each user position

    // Events
    event PlayerRegistered(address indexed player);
    event RequestFulfilled(uint256 requestId, uint256 randomWord);
    event PlayerMoved(address player, uint256 gameIndex, uint8 newPosition);
    event GameDurationUpdated(uint256 gameDuration);
    event ParticipationFeesUpdated(uint256 participationFee);
    event Received(address indexed sender, uint256 amount);

    // Errors
    error SquareAlreadyDrawn(uint8 squareIndex);
    error InvalidParticipationFee();
    error UserAlreadyRegistered(address user);
    error InvalidGameDuration(uint256 newGameDuration);
    error PlayerNotParticipated(address user);
    error GameNotActive();
    error UserTurnsExhausted(address user);
    error RequestNotFound(uint256 requestId);

    constructor(
        address rngCoordinator
    ) DRBConsumerBase(rngCoordinator) Ownable(msg.sender) {
        _initializeBoard();
    }

    // Modifiers

    /**
     * @dev Modifier to check if the player can take the next turn.
     */
    modifier playerRegistered() {
        User memory user = playerInfo[msg.sender];
        if (!user.validMember) {
            revert PlayerNotParticipated(msg.sender);
        }
        _;
    }

    /**
     * @dev Modifier to check if the game is active.
     */
    modifier gameActive() {
        if (!isGameActive) {
            revert GameNotActive();
        }
        _;
    }

    function play() external payable playerRegistered gameActive {
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
     * @dev Participate in the game by paying the participation fee.
     * @notice The participant must send Ether to join the game.
     * If the player has already registered for the current game round, the transaction will revert.
     * Emits a {PlayerRegistered} event.
     */
    function participate() external payable {
        if (msg.value < participationFee) {
            revert InvalidParticipationFee();
        }
        User storage user = playerInfo[msg.sender];
        if (user.validMember) {
            revert UserAlreadyRegistered(msg.sender);
        }

        user.validMember = true;
        totalBalance += msg.value;

        emit PlayerRegistered(msg.sender);
    }

    /**
     * @dev Updates the game duration.
     * @param _newGameDuration The new game duration in seconds.
     * @notice Only the contract owner can call this function.
     * @dev Reverts if the new duration is the same as the current one.
     */
    function updateGameDuration(uint256 _newGameDuration) external onlyOwner {
        if (_newGameDuration == gameDuration || _newGameDuration == 0) {
            revert InvalidGameDuration(_newGameDuration);
        }

        gameDuration = _newGameDuration;

        emit GameDurationUpdated(_newGameDuration);
    }

    /**
     * @dev Updates the participation fee.
     * @param _newParticipationFee The new participation fee in wei.
     * @notice Only the contract owner can call this function.
     * @dev Reverts if the new fee is zero or the same as the current one.
     */
    function updateParticipationFee(
        uint256 _newParticipationFee
    ) external onlyOwner {
        if (
            _newParticipationFee == participationFee ||
            _newParticipationFee == 0
        ) {
            revert InvalidParticipationFee();
        }

        participationFee = _newParticipationFee;

        emit ParticipationFeesUpdated(_newParticipationFee);
    }

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

    function _initializeBoard() internal {
        titles.push(Title(1, int8(100), 1));
        titles.push(Title(2, int8(30), 3));
        titles.push(Title(3, int8(20), 10));
        titles.push(Title(4, int8(10), 40));
        titles.push(Title(5, int8(-5), 46));

        // Randomly fill the board
        for (uint256 i = 0; i < BOARD_SIZE; i++) {
            uint256 randomIndex = _getRandomNumber(i);

            Title memory title = titles[randomIndex];

            // Check if the title can be placed
            if (title.maxCount > 0) {
                gameBoard[i] = title.points;
                title.maxCount--;
                titles[randomIndex] = title;
            } else {
                // If the title cannot be placed, find another one (loop prevented)
                bool foundValidTitle = false;
                while (!foundValidTitle) {
                    randomIndex = _getRandomNumber(i);
                    title = titles[randomIndex];
                    if (title.maxCount > 0) {
                        foundValidTitle = true;
                    }
                }

                gameBoard[i] = title.points;
                title.maxCount--;
                titles[randomIndex] = title;
            }
        }
    }

    function _getRandomNumber(uint256 i) internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.prevrandao,
                        msg.sender,
                        i
                    )
                )
            );
    }
}
