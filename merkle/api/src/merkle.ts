import { StandardMerkleTree } from "@ericnordelo/strk-merkle-tree";
import { hash } from "starknet";

export interface MerkleEntry {
  address: string;
  count: number;
}

export interface MerkleResult {
  root: string;
  entries: Array<{ address: string; count: number; proof: string[] }>;
}

/**
 * Compute the leaf value matching the Cairo contract:
 *   PedersenTrait::new(0).update(address).update(count).finalize()
 */
function computeLeafValue(address: string, count: number): string {
  const intermediate = hash.computePedersenHash("0x0", address);
  return hash.computePedersenHash(intermediate, "0x" + count.toString(16));
}

/**
 * Build a merkle tree and compute all proofs.
 */
export function buildTreeWithProofs(entries: MerkleEntry[]): MerkleResult {
  const leaves = entries.map((e) => [computeLeafValue(e.address, e.count)]);

  const tree = StandardMerkleTree.of(leaves, ["felt252"], {
    sortLeaves: true,
  });

  const results: MerkleResult["entries"] = [];

  for (const [index, leaf] of tree.entries()) {
    // Find which entry this leaf corresponds to
    const leafValue = leaf[0] as string;
    const entry = entries.find(
      (e) => BigInt(computeLeafValue(e.address, e.count)) === BigInt(leafValue),
    );
    if (entry) {
      results.push({
        address: entry.address,
        count: entry.count,
        proof: tree.getProof(index),
      });
    }
  }

  return { root: tree.root, entries: results };
}
