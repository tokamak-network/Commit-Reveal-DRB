// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DRBConsumerBase} from "./DRBConsumerBase.sol";
import {TickBitmap} from "./libraries/TickBitmap.sol";

/**
 * @title RareTitle
 * @notice This contract implements a game where players can earn points by
 *         claiming titles on a board. The game uses DRBCoordinator for random number
 *         generation and rewards players with tokens.
 */
contract RareTitle is DRBConsumerBase, ReentrancyGuard, Ownable {
    using TickBitmap for mapping(int16 => uint256);

    enum RequestStatus {
        NOTREQUESTED,
        REQUESTED,
        FULFILLED,
        REFUNDED
    }
    // Struct to store player information
    struct User {
        int24 totalPoints;
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
    uint32 public constant CALLBACK_GAS_LIMIT = 150000; // Depends on the number of requested values that you request
    int24 private constant TICK_SPACING = 5;
    int24 private constant MIN_TICK = -50;
    int24 private constant MAX_TICK_PLUS_ONE = 1001;
    uint8 private constant BLACKLIST_TOTALTURNS = 255;

    // Storage Variables
    IERC20 public tonToken;
    uint256 public reward; // Total TON reward set by the owner

    uint256 private gameExpiry; // Time at which the game expires
    uint256 private refundRequestId;
    mapping(address => User) private playerInfo; // Mapping of each user position
    mapping(int16 wordPos => uint256) private tickBitmap;
    mapping(int24 score => uint256 count) private scoreCount;
    mapping(int24 score => address[] players) private scoreToPlayers;
    mapping(address player => uint256 scoreToPlayersOrder)
        private scoreToPlayersOrder;

    // Events
    event RequestFulfilled(uint256 requestId, uint256 randomWord);
    event GameExpiryUpdated(uint256 gameExpiry);
    event FundsWithdrawn(uint256 amount);

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
    error NoWinners();

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
        gameExpiry = _gameExpiry + block.timestamp;

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

    function viewTotalPoints() public view returns (int24 totalPoints) {
        User memory user = playerInfo[msg.sender];
        totalPoints = user.totalPoints;
    }

    function viewRemainingTurns() public view returns (uint256 remainingTurns) {
        User memory user = playerInfo[msg.sender];
        if (user.totalTurns >= MAX_NO_OF_TURNS) {
            remainingTurns = 0;
        } else remainingTurns = MAX_NO_OF_TURNS - user.totalTurns;
    }

    function viewEventInfos()
        public
        view
        returns (
            uint256[] memory requestIds,
            uint256[] memory randomNumbers,
            uint8[] memory requestStatus,
            int24 totalPoints,
            uint8 totalTurns,
            int24[] memory _winnerPoint,
            uint256[] memory winnerLength,
            uint256[] memory prizeAmounts,
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
        (_winnerPoint, winnerLength, prizeAmounts) = _getWinnerScoreAndCount();
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
        if (user.totalTurns >= MAX_NO_OF_TURNS) {
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
        RequestInfo storage request = s_requests[_requestId];
        if (request.status != RequestStatus.REQUESTED) {
            revert RequestNotFound(_requestId);
        }
        request.status = RequestStatus.FULFILLED;
        request.randomNumber = _randomWord;
        address _player = request.player;
        int24 addPoint;
        uint256 modBoardSize = _randomWord % BOARD_SIZE;
        if (modBoardSize > 53) addPoint = -5;
        else if (modBoardSize > 13) addPoint = 10;
        else if (modBoardSize > 3) addPoint = 20;
        else if (modBoardSize > 0) addPoint = 30;
        else addPoint = 100;
        int24 scoreBefore = playerInfo[_player].totalPoints;
        int24 scoreAfter;
        unchecked {
            scoreAfter = scoreBefore + addPoint;
        }
        address[] storage _scoreToPlayers;
        uint256 order = scoreToPlayersOrder[_player];
        if (order != 0) {
            if (--scoreCount[scoreBefore] == 0)
                tickBitmap.flipTick(scoreBefore, TICK_SPACING);

            _scoreToPlayers = scoreToPlayers[scoreBefore];
            if (_scoreToPlayers.length > 1) {
                address lastPlayer = _scoreToPlayers[
                    _scoreToPlayers.length - 1
                ];
                _scoreToPlayers[order - 1] = lastPlayer;
                scoreToPlayersOrder[lastPlayer] = order;
            }
            _scoreToPlayers.pop();
        }
        if (++scoreCount[scoreAfter] == 1)
            tickBitmap.flipTick(scoreAfter, TICK_SPACING);

        // update scoreAfter
        playerInfo[_player].totalPoints = scoreAfter;
        _scoreToPlayers = scoreToPlayers[scoreAfter];
        _scoreToPlayers.push(_player);
        scoreToPlayersOrder[_player] = _scoreToPlayers.length;
    }

    function blackList(address[] calldata players) external onlyOwner {
        for (uint256 i = 0; i < players.length; i++) {
            address player = players[i];
            playerInfo[player].totalTurns = BLACKLIST_TOTALTURNS;
            int24 score = playerInfo[player].totalPoints;
            // update scoreBefore
            uint256 order = scoreToPlayersOrder[player];
            if (order != 0) {
                if (--scoreCount[score] == 0)
                    tickBitmap.flipTick(score, TICK_SPACING);
                address[] storage _scoreToPlayers = scoreToPlayers[score];
                if (_scoreToPlayers.length > 1) {
                    address lastPlayer = _scoreToPlayers[
                        _scoreToPlayers.length - 1
                    ];
                    _scoreToPlayers[order - 1] = lastPlayer;
                    scoreToPlayersOrder[lastPlayer] = order;
                }
                _scoreToPlayers.pop();
            }
        }
    }

    function getRefund(uint256 requestId) external override nonReentrant {
        refundRequestId = requestId;
        i_drbCoordinator.getRefund(requestId);
    }

    function claimPrize() external gameExpired onlyOwner {
        uint256 balance = tonToken.balanceOf(address(this));

        if (balance < reward) {
            revert InsufficientBalance(balance, reward);
        }

        (
            int24[] memory winnerScores,
            uint256[] memory winnerLengths,
            uint256[] memory prizeAmounts
        ) = _getWinnerScoreAndCount();
        if (winnerScores.length == 0) {
            revert NoWinners();
        } else if (winnerScores.length == 1) {
            address[] memory winners = scoreToPlayers[winnerScores[0]];
            for (uint256 i = 0; i < winnerLengths[0]; i++) {
                tonToken.transfer(winners[i], prizeAmounts[0]);
            }
        } else {
            address[] memory winners = scoreToPlayers[winnerScores[0]];
            tonToken.transfer(winners[0], prizeAmounts[0]);
            uint256 i = 1;
            while (i < 5) {
                if (winnerLengths[i] == 0) {
                    break;
                }
                for (uint256 j = 0; j < winnerLengths[i]; j++) {
                    tonToken.transfer(
                        scoreToPlayers[winnerScores[i]][j],
                        prizeAmounts[i]
                    );
                }
                unchecked {
                    ++i;
                }
            }
        }
    }

    function getWinnersInfo()
        external
        view
        returns (
            int24[] memory winnerPoint,
            uint256[] memory winnerLength,
            uint256[] memory prizeAmounts,
            address[][] memory winners
        )
    {
        (winnerPoint, winnerLength, prizeAmounts) = _getWinnerScoreAndCount();
        if (winnerPoint.length == 0) {
            return (winnerPoint, winnerLength, prizeAmounts, winners);
        } else if (winnerPoint.length == 1) {
            winners = new address[][](1);
            winners[0] = scoreToPlayers[winnerPoint[0]];
        } else {
            winners = new address[][](5);
            for (uint256 i = 0; i < 5; i++) {
                if (winnerLength[i] == 0) {
                    break;
                }
                winners[i] = scoreToPlayers[winnerPoint[i]];
            }
        }
    }

    function _getWinnerScoreAndCount()
        internal
        view
        returns (
            int24[] memory winners,
            uint256[] memory scoreCounts,
            uint256[] memory prizeAmounts
        )
    {
        int24 currentTick = MAX_TICK_PLUS_ONE;
        bool found;
        (currentTick, found) = _findLeftInitializedTick(currentTick);
        if (!found) return (winners, scoreCounts, prizeAmounts); // no winners
        uint256 count = scoreCount[currentTick];
        if (count > 1) {
            // only 1st exists
            winners = new int24[](1);
            scoreCounts = new uint256[](1);
            prizeAmounts = new uint256[](1);
            winners[0] = currentTick;
            scoreCounts[0] = count;
            prizeAmounts[0] = reward / count;
            return (winners, scoreCounts, prizeAmounts);
        }
        uint256 leftReward = reward / 2;
        winners = new int24[](5);
        scoreCounts = new uint256[](5);
        prizeAmounts = new uint256[](5);
        prizeAmounts[0] = leftReward;
        winners[0] = currentTick;
        scoreCounts[0] = 1;
        uint256 totalCount = 1;
        uint256 i = 1;
        do {
            (currentTick, found) = _findLeftInitializedTick(currentTick - 1);
            if (!found) break;
            winners[i] = currentTick;
            scoreCounts[i] = scoreCount[currentTick];
            totalCount += scoreCounts[i];
            if (totalCount <= 5) {
                leftReward -= 125 ether * scoreCounts[i];
                prizeAmounts[i] = 125 ether;
            } else {
                prizeAmounts[i] = leftReward / scoreCounts[i];
                break;
            }
            if (totalCount >= 5) {
                break;
            }
            unchecked {
                ++i;
            }
        } while (i < 5);
    }

    function _findLeftInitializedTick(
        int24 currentTick
    ) private view returns (int24, bool found) {
        while (currentTick > MIN_TICK) {
            (int24 nextTick, bool initialized) = tickBitmap
                .nextInitializedTickWithinOneWord(
                    currentTick,
                    TICK_SPACING,
                    true
                );
            if (initialized) {
                currentTick = nextTick;
                found = true;
                break;
            }
            unchecked {
                --currentTick;
            }
        }
        return (currentTick, found);
    }
}
