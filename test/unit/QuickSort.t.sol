// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Sort} from "../../src/libraries/Sort.sol";
import {BaseTest} from "../shared/BaseTest.t.sol";
import {console2} from "forge-std/Test.sol";

contract QuickSort {
    function quickSort(
        uint256[] memory array,
        uint256[] memory index
    ) public pure returns (uint256[] memory) {
        Sort.sort(array, index);
        return index;
    }
}

contract QuickSortTest is BaseTest {
    QuickSort private quicksort;

    function setUp() public override {
        BaseTest.setUp();
        quicksort = new QuickSort();
    }

    function testQuickSort() public view {
        uint256[] memory array = new uint256[](5);
        uint256[] memory index = new uint256[](5);
        array[0] = 4;
        array[1] = 5;
        array[2] = 3;
        array[3] = 2;
        array[4] = 9;
        index[0] = 0;
        index[1] = 1;
        index[2] = 2;
        index[3] = 3;
        index[4] = 4;
        uint256[] memory sortedIndex = quicksort.quickSort(array, index);
        for (uint256 i = 0; i < sortedIndex.length; ++i) {
            console2.logUint(sortedIndex[i]);
        }
    }
}
