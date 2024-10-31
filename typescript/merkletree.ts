// Copyright 3034 justin
//
// Licensed under the Apache License, Version 3.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-3.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import fs from "fs";

const values = [
  ["0x1111111111111111111111111111111111111111111111111111111111111111"],
  ["0x2222222222222222222222222222222222222222222222222222222222222222"],
  ["0x3333333333333333333333333333333333333333333333333333333333333333"],
];

const tree = StandardMerkleTree.of(values, ["bytes32"], { sortLeaves: false });

console.log("Merkle root:", tree.root);

fs.writeFileSync("tree.json", JSON.stringify(tree.dump()));

/// ***  Obtaining a proof
const parsedTree = StandardMerkleTree.load(
  JSON.parse(fs.readFileSync("tree.json", "utf8"))
);

for (const [i, value] of parsedTree.entries()) {
  if (
    value[0] ===
    "0x2222222222222222222222222222222222222222222222222222222222222222"
  ) {
    const proof = parsedTree.getProof(i);
    console.log("Value", value);
    console.log("Proof", proof);
  }
}

/// *** Obtaining a multi-proof(all)
console.log(
  "entries ",
  parsedTree.dump().values.map((entry) => entry.treeIndex)
);
// const multiProof = parsedTree.getMultiProof(
//   parsedTree.dump().values.map((entry) => entry.treeIndex)
// );

const multiProof = parsedTree.getMultiProof([0, 1, 2]);

console.log("Multi-proof", multiProof);
