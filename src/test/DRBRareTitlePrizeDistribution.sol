// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {TickBitmap} from "../libraries/TickBitmap.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/Test.sol";

contract RareTitlePrizeDistribution {
    using TickBitmap for mapping(int16 => uint256);
    enum RequestStatus {
        NOTREQUESTED,
        REQUESTED,
        FULFILLED,
        REFUNDED
    }

    struct RequestInfo {
        address player;
        uint256 randomNumber;
        RequestStatus status;
    }

    // Struct to store player information
    struct User {
        int24 totalPoints;
        uint8 totalTurns;
        uint256[] requestIds;
    }
    error InsufficientBalance(uint256 required, uint256 actual);
    error NoWinners();

    uint256 public reward;
    IERC20 public tonToken;
    uint8 public constant BLACKLIST_TOTALTURNS = 255;
    mapping(uint256 requestId => RequestInfo requestInfo) public s_requests;
    mapping(address => User) public playerInfo; // Mapping of each user position
    int24 public constant TICK_SPACING = 5;
    mapping(int24 score => uint256 count) public scoreCount;

    uint256 public constant BOARD_SIZE = 100;
    mapping(int16 wordPos => uint256) public tickBitmap;

    mapping(address player => uint256 scoreToPlayersOrder)
        public scoreToPlayersOrder;
    mapping(int24 score => address[] players) public scoreToPlayers;
    int24 public constant MIN_TICK = -50;
    int24 public constant MAX_TICK_PLUS_ONE = 1001;

    constructor(address _tonToken) {
        tonToken = IERC20(_tonToken);
        reward = 1000 ether;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256 _randomWord
    ) public {
        RequestInfo storage request = s_requests[_requestId];
        request.player = msg.sender;
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

    function blackList(address[] calldata players) external {
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

    function claimPrize() external {
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
    ) public view returns (int24, bool found) {
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
