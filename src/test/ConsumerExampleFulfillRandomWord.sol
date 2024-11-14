// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {IDRBCoordinator} from "../interfaces/IDRBCoordinator.sol";

contract ConsumerExampleFulfillRandomWord {
    struct RequestStatus {
        bool requested; // whether the request has been made
        bool fulfilled; // whether the request has been successfully fulfilled
        uint256 randomNumber;
    }

    mapping(uint256 => RequestStatus)
        public s_requests; /* requestId --> requestStatus */

    // past requests Id.
    uint256[] public requestIds;
    address s_owner;
    uint32 public constant CALLBACK_GAS_LIMIT = 83011;

    error OnlyCoordinatorCanFulfill(address have, address want);
    error InvalidRequest(uint256 requestId);

    /// @dev The RNGCoordinator contract
    IDRBCoordinator internal immutable i_drbCoordinator;

    constructor(address rngCoordinator) {
        s_owner = msg.sender;
        i_drbCoordinator = IDRBCoordinator(rngCoordinator);
        for (uint256 i; i < 10; i++) {
            s_requests[i].requested = true;
        }
        _initializeBoard();
        for (uint256 i = 100; i < 120; i++) {
            s_requests2[i].status = RequestStatus2.REQUESTED;
        }
    }

    function rawFulfillRandomWords(
        uint256 requestId,
        uint256 randomNumber
    ) external {
        require(
            msg.sender == s_owner,
            OnlyCoordinatorCanFulfill(msg.sender, address(i_drbCoordinator))
        );
        fulfillRandomWords(requestId, randomNumber);
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256 hashedOmegaVal
    ) internal {
        if (!s_requests[requestId].requested) {
            revert InvalidRequest(requestId);
        }
        s_requests[requestId].fulfilled = true;
        s_requests[requestId].randomNumber = hashedOmegaVal;
    }

    function rawFulfillRandomWords2(
        uint256 requestId,
        uint256 randomNumber
    ) external {
        require(
            msg.sender == s_owner,
            OnlyCoordinatorCanFulfill(msg.sender, address(i_drbCoordinator))
        );
        fulfillRandomWords3(requestId, randomNumber);
    }

    enum RequestStatus2 {
        NOTREQUESTED,
        REQUESTED,
        FULFILLED,
        REFUNDED
    }

    struct RequestInfo {
        address player;
        uint256 randomNumber;
        RequestStatus2 status;
    }

    struct User {
        int16 totalPoints;
        uint8 totalTurns;
        uint256[] requestIds;
    }

    uint8 public constant BOARD_SIZE = 100;
    mapping(address => User) private playerInfo;
    int8[BOARD_SIZE] private gameBoard;
    int16 public winnerPoint;
    address[] private winners;
    mapping(uint256 requestId => RequestInfo requestInfo) public s_requests2;

    function fulfillRandomWords2(
        uint256 _requestId,
        uint256 _randomWord
    ) internal {
        if (s_requests2[_requestId].status != RequestStatus2.REQUESTED) {
            revert InvalidRequest(_requestId);
        }
        RequestInfo storage request = s_requests2[_requestId];
        request.status = RequestStatus2.FULFILLED;
        request.randomNumber = _randomWord;
        address _player = request.player;
        User storage player = playerInfo[_player];
        int16 myTotalPoint;
        unchecked {
            myTotalPoint = player.totalPoints += gameBoard[
                _randomWord % BOARD_SIZE
            ];
        }
        if (myTotalPoint > winnerPoint) {
            winnerPoint = myTotalPoint;
            delete winners;
            winners.push(_player);
        } else if (myTotalPoint == winnerPoint) {
            winners.push(_player);
        }
    }

    function fulfillRandomWords3(
        uint256 _requestId,
        uint256 _randomWord
    ) internal {
        if (s_requests2[_requestId].status != RequestStatus2.REQUESTED) {
            revert InvalidRequest(_requestId);
        }
        RequestInfo storage request = s_requests2[_requestId];
        request.status = RequestStatus2.FULFILLED;
        request.randomNumber = _randomWord;
        address _player = request.player;
        User storage player = playerInfo[_player];
        int16 myTotalPoint;
        int16 addPoint;
        uint256 modBoardSize = _randomWord % BOARD_SIZE;
        // if (modBoardSize == 1) addPoint = 100;
        // else if (modBoardSize < 4) addPoint = 30;
        // else if (modBoardSize < 14) addPoint = 20;
        // else if (modBoardSize < 54) addPoint = 10;
        // else addPoint = -5;
        if (modBoardSize > 53) addPoint = -5;
        else if (modBoardSize > 13) addPoint = 10;
        else if (modBoardSize > 3) addPoint = 20;
        else if (modBoardSize > 0) addPoint = 30;
        else addPoint = 100;
        unchecked {
            myTotalPoint = player.totalPoints += addPoint;
        }
        if (myTotalPoint > winnerPoint) {
            winnerPoint = myTotalPoint;
            delete winners;
            winners.push(_player);
        } else if (myTotalPoint == winnerPoint) {
            winners.push(_player);
        }
    }

    struct Title {
        int8 points;
        uint8 maxCount;
    }
    Title[] public titles;

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
