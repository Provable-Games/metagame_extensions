import { StandardMerkleTree } from "@ericnordelo/strk-merkle-tree";
import { hash } from "starknet";

export interface MerkleEntry {
  address: string;
  count: number;
}

/**
 * Compute the leaf value matching the Cairo contract:
 *   PedersenTrait::new(0).update(address).update(count).finalize()
 */
export function computeLeafValue(address: string, count: number): string {
  const intermediate = hash.computePedersenHash("0x0", address);
  return hash.computePedersenHash(intermediate, "0x" + count.toString(16));
}

/**
 * Build a merkle tree from entries. Returns the root and a serializable dump.
 */
export function buildTree(entries: MerkleEntry[]) {
  const leaves = entries.map((e) => [computeLeafValue(e.address, e.count)]);

  const tree = StandardMerkleTree.of(leaves, ["felt252"], {
    sortLeaves: true,
  });

  return { root: tree.root, dump: tree.dump() };
}

/**
 * In-memory cache of leaf-value-to-index mappings per tree id.
 * Avoids O(n) scans when generating proofs for large trees.
 */
const leafIndexCache = new Map<number, Map<bigint, number>>();

/**
 * Build (or retrieve from cache) a Map from leaf BigInt value to its index
 * in the merkle tree, enabling O(1) proof lookups.
 */
function getLeafIndexMap(
  treeId: number,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  treeDump: any,
): Map<bigint, number> {
  const cached = leafIndexCache.get(treeId);
  if (cached) return cached;

  const tree = StandardMerkleTree.load(treeDump);
  const indexMap = new Map<bigint, number>();
  for (const [index, leaf] of tree.entries()) {
    indexMap.set(BigInt(leaf[0] as string), index);
  }
  leafIndexCache.set(treeId, indexMap);
  return indexMap;
}

/**
 * Get proof for an address from a tree dump using cached O(1) index lookup.
 */
export function getProofFromDump(
  treeId: number,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  treeDump: any,
  address: string,
  count: number,
): string[] | null {
  const tree = StandardMerkleTree.load(treeDump);
  const leafValue = computeLeafValue(address, count);
  const indexMap = getLeafIndexMap(treeId, treeDump);
  const index = indexMap.get(BigInt(leafValue));
  if (index !== undefined) {
    return tree.getProof(index);
  }
  return null;
}
