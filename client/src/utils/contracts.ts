// Re-export all ABIs from SDK
export {
  SNAPSHOT_VALIDATOR_ABI,
  ERC20_BALANCE_VALIDATOR_ABI,
  GOVERNANCE_VALIDATOR_ABI,
  OPUS_TROVES_VALIDATOR_ABI,
  TOURNAMENT_VALIDATOR_ABI,
  ZK_PASSPORT_VALIDATOR_ABI,
  MERKLE_VALIDATOR_ABI,
} from "@provable-games/metagame-sdk/abis";

// Type definitions
export interface Entry {
  address: string;
  count: number;
}

export interface SnapshotMetadata {
  owner: string;
  status: "Created" | "InProgress" | "Locked";
}
