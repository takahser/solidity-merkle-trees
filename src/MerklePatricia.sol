pragma solidity ^0.8.17;

import "./trie/Node.sol";
import "./trie/Option.sol";
import "./trie/NibbleSlice.sol";
import "./trie/TrieDB.sol";

import "./trie/substrate/SubstrateTrieDB.sol";
import "./trie/ethereum/EthereumTrieDB.sol";

// SPDX-License-Identifier: Apache2

/**
 * @title A Merkle Patricia library
 * @author Polytope Labs
 * @dev Use this library to verify merkle patricia proofs
 * @dev refer to research for more info. https://research.polytope.technology/state-(machine)-proofs
 */
library MerklePatricia {
     /// @notice libraries in solidity can only have constant variables
     /// @dev MAX_TRIE_DEPTH, we don't explore deeply nested trie keys.
     uint256 internal constant MAX_TRIE_DEPTH = 50;

     /**
      * @notice Verifies substrate specific merkle patricia proofs.
      * @param root hash of the merkle patricia trie
      * @param proof a list of proof nodes
      * @param keys a list of keys to verify
      * @return bytes[] a list of values corresponding to the supplied keys.
      */
     function VerifySubstrateProof(bytes32 root, bytes[] memory proof,  bytes[] memory keys)
          internal
          pure
          returns (bytes[] memory)
     {
          bytes[] memory values = new bytes[](keys.length);
          TrieNode[] memory nodes = new TrieNode[](proof.length);

          for (uint256 i = 0; i < proof.length; i++) {
               nodes[i] = TrieNode(keccak256(proof[i]), proof[i]);
          }

          for (uint256 i = 0; i < keys.length; i++) {
               NibbleSlice memory keyNibbles = NibbleSlice(keys[i], 0);
               NodeKind memory node = SubstrateTrieDB.decodeNodeKind(TrieDB.get(nodes, root));

               // worst case scenario, so we avoid unbounded loops
               for (uint256 j = 0; j < MAX_TRIE_DEPTH; j++) {
                    NodeHandle memory nextNode;

                    if (TrieDB.isLeaf(node)) {
                         Leaf memory leaf = SubstrateTrieDB.decodeLeaf(node);
                         if (NibbleSliceOps.eq(leaf.key, keyNibbles)) {
                              values[i] = TrieDB.load(nodes, leaf.value);
                         }
                         break;
                    }  else if (TrieDB.isNibbledBranch(node)) {
                         NibbledBranch memory nibbled = SubstrateTrieDB.decodeNibbledBranch(node);
                         uint256 nibbledBranchKeyLength = NibbleSliceOps.len(nibbled.key);
                         if (!NibbleSliceOps.startsWith(keyNibbles, nibbled.key)) {
                              break;
                         }

                         if (NibbleSliceOps.len(keyNibbles) == nibbledBranchKeyLength) {
                              if (Option.isSome(nibbled.value)) {
                                   values[i] = TrieDB.load(nodes, nibbled.value.value);
                              }
                              break;
                         } else {
                              uint256 index = NibbleSliceOps.at(keyNibbles, nibbledBranchKeyLength);
                              NodeHandleOption memory handle = nibbled.children[index];
                              if (Option.isSome(handle)) {
                                   keyNibbles = NibbleSliceOps.mid(keyNibbles, nibbledBranchKeyLength + 1);
                                   nextNode = handle.value;
                              } else {
                                   break;
                              }
                         }
                    }  else if (TrieDB.isEmpty(node)) {
                         break;
                    }

                    node = SubstrateTrieDB.decodeNodeKind(TrieDB.load(nodes, nextNode));
               }
          }

          return values;
     }

     /**
      * @notice Verify child trie keys
      * @dev substrate specific method in order to verify keys in the child trie.
      * @param root hash of the merkle root
      * @param proof a list of proof nodes
      * @param keys a list of keys to verify
      * @param childInfo data that can be used to compute the root of the child trie
      * @return bytes[], a list of values corresponding to the supplied keys.
      */
     function ReadChildProofCheck(bytes32 root, bytes[] memory proof, bytes[] memory keys, bytes memory childInfo)
          internal
          pure
          returns (bytes[] memory)
     {
          // fetch the child trie root hash;
          bytes memory prefix = bytes(":child_storage:default:");
          bytes memory key = bytes.concat(prefix, childInfo);
          bytes[] memory _keys = new bytes[](1);
          _keys[0] = key;
          bytes[] memory values  = VerifySubstrateProof(root, proof, _keys);

          bytes32 childRoot = bytes32(values[0]);
          require(childRoot != bytes32(0), "Invalid child trie proof");
          
          return VerifySubstrateProof(childRoot, proof, keys);
     }

     /**
      * @notice Verifies ethereum specific merkle patricia proofs as described by EIP-1188.
      * @param root hash of the merkle patricia trie
      * @param proof a list of proof nodes
      * @param keys a list of keys to verify
      * @return bytes[] a list of values corresponding to the supplied keys.
      */
     function VerifyEthereumProof(bytes32 root, bytes[] memory proof,  bytes[] memory keys)
          internal
          pure
          returns (bytes[] memory)
     {
          bytes[] memory values = new bytes[](keys.length);
          TrieNode[] memory nodes = new TrieNode[](proof.length);

          for (uint256 i = 0; i < proof.length; i++) {
               nodes[i] = TrieNode(keccak256(proof[i]), proof[i]);
          }

          for (uint256 i = 0; i < keys.length; i++) {
               NibbleSlice memory keyNibbles = NibbleSlice(keys[i], 0);
               NodeKind memory node = EthereumTrieDB.decodeNodeKind(TrieDB.get(nodes, root));

               // worst case scenario, so we avoid unbounded loops
               for (uint256 j = 0; j < MAX_TRIE_DEPTH; j++) {
                    NodeHandle memory nextNode;

                    if (TrieDB.isLeaf(node)) {
                         Leaf memory leaf = EthereumTrieDB.decodeLeaf(node);
                         if (NibbleSliceOps.eq(leaf.key, keyNibbles)) {
                              values[i] = TrieDB.load(nodes, leaf.value);
                         }
                         break;
                    } else if (TrieDB.isExtension(node)) {
                         Extension memory extension = EthereumTrieDB.decodeExtension(node);
                         if (NibbleSliceOps.startsWith(keyNibbles, extension.key)) {
                              uint256 len = NibbleSliceOps.len(extension.key);
                              keyNibbles = NibbleSliceOps.mid(keyNibbles, len);
                              nextNode = extension.node;
                         } else {
                              break;
                         }
                    } else if (TrieDB.isBranch(node)) {
                         Branch memory branch = EthereumTrieDB.decodeBranch(node);
                         if (NibbleSliceOps.isEmpty(keyNibbles)) {
                              if (Option.isSome(branch.value)) {
                                   values[i] = TrieDB.load(nodes, branch.value.value);
                              }
                              break;
                         } else {
                              NodeHandleOption memory handle = branch.children[NibbleSliceOps.at(keyNibbles, 0)];
                              if (Option.isSome(handle)) {
                                   keyNibbles = NibbleSliceOps.mid(keyNibbles, 1);
                                   nextNode = handle.value;
                              } else {
                                   break;
                              }
                         }
                    }  else if (TrieDB.isEmpty(node)) {
                         break;
                    }

                    node = EthereumTrieDB.decodeNodeKind(TrieDB.load(nodes, nextNode));
               }
          }

          return values;
     }
}