// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract MerkleTest {
    bytes32 public root;

    constructor(bytes32 _root) {
        root = _root;
    }

    function verify(bytes32[] memory proof, bytes32 commitment) public view {
        bytes32 leaf = keccak256(abi.encode(keccak256(abi.encode(commitment))));
        require(
            MerkleProof.verify(proof, root, leaf),
            "MerkleTest: Invalid proof"
        );
    }
}
