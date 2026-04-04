import { RpcProvider, CallData } from "starknet";

const rpcUrl =
  process.env.STARKNET_RPC_URL ??
  "https://api.cartridge.gg/x/starknet/sepolia";

const validatorAddress = process.env.MERKLE_VALIDATOR_ADDRESS ?? "";

const provider = new RpcProvider({ nodeUrl: rpcUrl });

/**
 * Fetch the on-chain merkle root for a given tree ID.
 * Returns the root as a hex string, or null if the call fails.
 */
export async function getOnChainTreeRoot(
  treeId: number,
): Promise<string | null> {
  if (!validatorAddress) return null;

  try {
    const result = await provider.callContract({
      contractAddress: validatorAddress,
      entrypoint: "get_tree_root",
      calldata: CallData.compile([treeId]),
    });
    // Result is a single felt252
    return result[0] ?? null;
  } catch (error) {
    console.error(`Failed to fetch on-chain root for tree ${treeId}:`, error);
    return null;
  }
}
