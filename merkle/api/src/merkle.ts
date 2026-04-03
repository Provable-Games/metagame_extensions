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
 * Get proof for an address from a tree dump. Computed on-demand.
 */
export function getProofFromDump(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  treeDump: any,
  address: string,
  count: number,
): string[] | null {
  const tree = StandardMerkleTree.load(treeDump);
  const leafValue = computeLeafValue(address, count);

  for (const [index, leaf] of tree.entries()) {
    if (BigInt(leaf[0] as string) === BigInt(leafValue)) {
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
