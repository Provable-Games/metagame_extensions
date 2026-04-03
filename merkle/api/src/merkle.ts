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
export function getLeafIndexMap(
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
 * Invalidate the cached leaf index map for a tree (e.g. if the tree is rebuilt).
 */
export function invalidateLeafIndexCache(treeId: number): void {
  leafIndexCache.delete(treeId);
}

/**
 * Get proof for an address from a tree dump. Computed on-demand.
 * When treeId is provided, uses a cached leaf-to-index map for O(1) lookup.
 */
export function getProofFromDump(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  treeDump: any,
  address: string,
  count: number,
  treeId?: number,
): string[] | null {
  const tree = StandardMerkleTree.load(treeDump);
  const leafValue = computeLeafValue(address, count);
  const leafBigInt = BigInt(leafValue);

  // Fast path: use cached index map
  if (treeId !== undefined) {
    const indexMap = getLeafIndexMap(treeId, treeDump);
    const index = indexMap.get(leafBigInt);
    if (index !== undefined) {
      return tree.getProof(index);
    }
    return null;
  }

  // Fallback: O(n) scan for backward compatibility
  for (const [index, leaf] of tree.entries()) {
    if (BigInt(leaf[0] as string) === leafBigInt) {
      return tree.getProof(index);
    }
  }

  return null;
}

/**
 * Find an entry's count from a tree dump by address.
 */
export function findEntryInDump(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  treeDump: any,
  entries: MerkleEntry[],
  address: string,
): MerkleEntry | null {
  const normalized = address.toLowerCase();
  return (
    entries.find(
      (e) =>
        e.address.toLowerCase() === normalized ||
        BigInt(e.address) === BigInt(address),
    ) || null
  );
}
