import { type Chain, mainnet, sepolia } from "@starknet-react/chains";
import {
  getExtensionAddresses,
  getMerkleApiUrl as sdkGetMerkleApiUrl,
  setMerkleApiUrl,
} from "@provable-games/metagame-sdk";

export type ChainId = "SN_MAIN" | "SN_SEPOLIA";

export interface ChainConfig {
  chainId: ChainId;
  chain: Chain;
  networkName: "mainnet" | "sepolia";
  rpcUrl: string;
  explorerUrl: string;
  snapshotValidatorAddress: `0x${string}`;
  erc20BalanceValidatorAddress?: `0x${string}`;
  governanceValidatorAddress?: `0x${string}`;
  opusTrovesValidatorAddress?: `0x${string}`;
  tournamentValidatorAddress?: `0x${string}`;
  zkPassportValidatorAddress?: `0x${string}`;
  merkleValidatorAddress?: `0x${string}`;
}

// Configure merkle API URL overrides from env vars
if (import.meta.env.VITE_SEPOLIA_MERKLE_API_URL) {
  setMerkleApiUrl("SN_SEPOLIA", import.meta.env.VITE_SEPOLIA_MERKLE_API_URL);
}
if (import.meta.env.VITE_MAINNET_MERKLE_API_URL) {
  setMerkleApiUrl("SN_MAIN", import.meta.env.VITE_MAINNET_MERKLE_API_URL);
}

export function getMerkleApiUrl(chainId: ChainId): string {
  return sdkGetMerkleApiUrl(chainId);
}

export const CHAIN_ID_FELTS: Record<ChainId, string> = {
  SN_MAIN: "0x534e5f4d41494e",
  SN_SEPOLIA: "0x534e5f5345504f4c4941",
};

const mainnetAddrs = getExtensionAddresses("SN_MAIN");
const sepoliaAddrs = getExtensionAddresses("SN_SEPOLIA");

const NETWORKS: Record<ChainId, ChainConfig> = {
  SN_MAIN: {
    chainId: "SN_MAIN",
    chain: mainnet,
    networkName: "mainnet",
    rpcUrl:
      import.meta.env.VITE_MAINNET_RPC_URL ||
      "https://api.cartridge.gg/x/starknet/mainnet",
    explorerUrl: "https://voyager.online",
    snapshotValidatorAddress: (
      import.meta.env.VITE_MAINNET_SNAPSHOT_VALIDATOR_ADDRESS ||
      mainnetAddrs.snapshotValidator
    ) as `0x${string}`,
    erc20BalanceValidatorAddress: (
      import.meta.env.VITE_MAINNET_ERC20_BALANCE_VALIDATOR_ADDRESS ||
      mainnetAddrs.erc20BalanceValidator || undefined
    ) as `0x${string}` | undefined,
    tournamentValidatorAddress: (
      import.meta.env.VITE_MAINNET_TOURNAMENT_VALIDATOR_ADDRESS ||
      mainnetAddrs.tournamentValidator || undefined
    ) as `0x${string}` | undefined,
    governanceValidatorAddress: (
      import.meta.env.VITE_MAINNET_GOVERNANCE_VALIDATOR_ADDRESS ||
      mainnetAddrs.governanceValidator || undefined
    ) as `0x${string}` | undefined,
    opusTrovesValidatorAddress: (
      import.meta.env.VITE_MAINNET_OPUS_TROVES_VALIDATOR_ADDRESS ||
      mainnetAddrs.opusTrovesValidator || undefined
    ) as `0x${string}` | undefined,
    zkPassportValidatorAddress: (
      import.meta.env.VITE_MAINNET_ZK_PASSPORT_VALIDATOR_ADDRESS ||
      mainnetAddrs.zkPassportValidator || undefined
    ) as `0x${string}` | undefined,
    merkleValidatorAddress: (
      import.meta.env.VITE_MAINNET_MERKLE_VALIDATOR_ADDRESS ||
      mainnetAddrs.merkleValidator || undefined
    ) as `0x${string}` | undefined,
  },
  SN_SEPOLIA: {
    chainId: "SN_SEPOLIA",
    chain: sepolia,
    networkName: "sepolia",
    rpcUrl:
      import.meta.env.VITE_SEPOLIA_RPC_URL ||
      "https://api.cartridge.gg/x/starknet/sepolia",
    explorerUrl: "https://sepolia.voyager.online",
    snapshotValidatorAddress: (
      import.meta.env.VITE_SEPOLIA_SNAPSHOT_VALIDATOR_ADDRESS ||
      sepoliaAddrs.snapshotValidator
    ) as `0x${string}`,
    erc20BalanceValidatorAddress: (
      import.meta.env.VITE_SEPOLIA_ERC20_BALANCE_VALIDATOR_ADDRESS ||
      sepoliaAddrs.erc20BalanceValidator || undefined
    ) as `0x${string}` | undefined,
    tournamentValidatorAddress: (
      import.meta.env.VITE_SEPOLIA_TOURNAMENT_VALIDATOR_ADDRESS ||
      sepoliaAddrs.tournamentValidator || undefined
    ) as `0x${string}` | undefined,
    governanceValidatorAddress: (
      import.meta.env.VITE_SEPOLIA_GOVERNANCE_VALIDATOR_ADDRESS ||
      sepoliaAddrs.governanceValidator || undefined
    ) as `0x${string}` | undefined,
    opusTrovesValidatorAddress: (
      import.meta.env.VITE_SEPOLIA_OPUS_TROVES_VALIDATOR_ADDRESS ||
      sepoliaAddrs.opusTrovesValidator || undefined
    ) as `0x${string}` | undefined,
    zkPassportValidatorAddress: (
      import.meta.env.VITE_SEPOLIA_ZK_PASSPORT_VALIDATOR_ADDRESS ||
      sepoliaAddrs.zkPassportValidator || undefined
    ) as `0x${string}` | undefined,
    merkleValidatorAddress: (
      import.meta.env.VITE_SEPOLIA_MERKLE_VALIDATOR_ADDRESS ||
      sepoliaAddrs.merkleValidator || undefined
    ) as `0x${string}` | undefined,
  },
};

export function getDefaultChainId(): ChainId {
  const urlParams = new URLSearchParams(window.location.search);
  const urlNetwork = urlParams.get("network");
  if (urlNetwork === "sepolia") return "SN_SEPOLIA";
  if (urlNetwork === "mainnet") return "SN_MAIN";

  const envDefault = import.meta.env.VITE_DEFAULT_NETWORK;
  if (envDefault === "sepolia") return "SN_SEPOLIA";

  return "SN_MAIN";
}

export function getNetworkConfig(chainId: ChainId): ChainConfig {
  return NETWORKS[chainId];
}

export function getAllChains() {
  return [NETWORKS.SN_MAIN.chain, NETWORKS.SN_SEPOLIA.chain] as const;
}
