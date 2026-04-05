import { StandardMerkleTree } from "@ericnordelo/strk-merkle-tree";
import { hash } from "starknet";

export interface MerkleEntry {
  address: string;
  count: number;
}

export interface MerkleTreeData {
  version: 2;
  createdAt: string;
  entries: MerkleEntry[];
  root: string;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  tree: any; // StandardMerkleTree dump format
}

/**
 * Compute the leaf value that gets passed to StandardMerkleTree.
 * This matches the Cairo contract's leaf computation:
 *   PedersenTrait::new(0).update(address).update(count).finalize()
 *
 * The StandardMerkleTree then applies its own leaf hashing on top:
 *   H(0, value, 1) using PedersenCHasher
 */
export function computeLeafValue(address: string, count: number): string {
  const intermediate = hash.computePedersenHash("0x0", address);
  return hash.computePedersenHash(intermediate, "0x" + count.toString(16));
}

/**
 * Build a StandardMerkleTree from entries.
 * Each leaf is a single felt252 value (the pre-hashed leaf value).
 */
export function buildMerkleTree(entries: MerkleEntry[]): MerkleTreeData {
  if (entries.length === 0) {
    throw new Error("Cannot build merkle tree with no entries");
  }

  const leaves = entries.map((e) => [computeLeafValue(e.address, e.count)]);

  const tree = StandardMerkleTree.of(leaves, ["felt252"], {
    sortLeaves: true,
  });

  return {
    version: 2,
    createdAt: new Date().toISOString(),
    entries,
    root: tree.root,
    tree: tree.dump(),
  };
}

/**
 * Load a tree from saved data and get the proof for an address.
 */
export function getProof(
  treeData: MerkleTreeData,
  address: string,
  count: number,
): string[] | null {
  const tree = StandardMerkleTree.load(treeData.tree);
  const leafValue = computeLeafValue(address, count);

  for (const [index, leaf] of tree.entries()) {
    if (BigInt(leaf[0] as string) === BigInt(leafValue)) {
      return tree.getProof(index);
    }
  }

  return null;
}

/**
 * Verify a proof against a root (client-side).
 */
export function verifyProof(
  treeData: MerkleTreeData,
  address: string,
  count: number,
  proof: string[],
): boolean {
  const leafValue = computeLeafValue(address, count);
  return StandardMerkleTree.verify(treeData.root, ["felt252"], [leafValue], proof);
}

/**
 * Build qualification array for contract calls: [count, ...proof]
 */
export function buildQualification(count: number, proof: string[]): string[] {
  return ["0x" + count.toString(16), ...proof];
}

/**
 * Find an entry in the tree by address.
 */
export function findEntry(
  treeData: MerkleTreeData,
  address: string,
): MerkleEntry | null {
  return (
    treeData.entries.find(
      (e) =>
        e.address.toLowerCase() === address.toLowerCase() ||
        BigInt(e.address) === BigInt(address),
    ) || null
  );
}
