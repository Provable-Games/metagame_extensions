import { type Chain, mainnet, sepolia } from "@starknet-react/chains";

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

export const CHAIN_ID_FELTS: Record<ChainId, string> = {
  SN_MAIN: "0x534e5f4d41494e",
  SN_SEPOLIA: "0x534e5f5345504f4c4941",
};

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
      "0x03e6820e9e1cfb5c22465a86f469c651355f05397e29fc94de8e832d5f3d8ede"
    ) as `0x${string}`,
    erc20BalanceValidatorAddress: (
      import.meta.env.VITE_MAINNET_ERC20_BALANCE_VALIDATOR_ADDRESS ||
      "0x051f5fc1ddcffcb0bf548378e0166a5e5328fb4894efbab170e3fb1a4c0cdfdf"
    ) as `0x${string}`,
    tournamentValidatorAddress: (
      import.meta.env.VITE_MAINNET_TOURNAMENT_VALIDATOR_ADDRESS ||
      "0x0771b57c0709fc4407ff8b63d573f302b96fb03638364032fad734e3c310b9e0"
    ) as `0x${string}`,
    governanceValidatorAddress: import.meta.env
      .VITE_MAINNET_GOVERNANCE_VALIDATOR_ADDRESS as
      | `0x${string}`
      | undefined,
    opusTrovesValidatorAddress: import.meta.env
      .VITE_MAINNET_OPUS_TROVES_VALIDATOR_ADDRESS as
      | `0x${string}`
      | undefined,
    zkPassportValidatorAddress: import.meta.env
      .VITE_MAINNET_ZK_PASSPORT_VALIDATOR_ADDRESS as
      | `0x${string}`
      | undefined,
    merkleValidatorAddress: import.meta.env
      .VITE_MAINNET_MERKLE_VALIDATOR_ADDRESS as
      | `0x${string}`
      | undefined,
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
      import.meta.env.VITE_SEPOLIA_SNAPSHOT_VALIDATOR_ADDRESS || "0x05520239f16dc58c5dfdccb1f0480977e7fea18d4305e64f5eae88ae786a22fe"
    ) as `0x${string}`,
    erc20BalanceValidatorAddress: (
      import.meta.env.VITE_SEPOLIA_ERC20_BALANCE_VALIDATOR_ADDRESS ||
      "0x028112199f873e919963277b41ef1231365986e2fd7722501cd7d293de60b64e"
    ) as `0x${string}`,
    tournamentValidatorAddress: (
      import.meta.env.VITE_SEPOLIA_TOURNAMENT_VALIDATOR_ADDRESS ||
      "0x07eade45e4317b1a036e3a8123bb1f95215d37a6f6b0cea25cdd48030a932dfc"
    ) as `0x${string}`,
    governanceValidatorAddress: import.meta.env
      .VITE_SEPOLIA_GOVERNANCE_VALIDATOR_ADDRESS as
      | `0x${string}`
      | undefined,
    opusTrovesValidatorAddress: import.meta.env
      .VITE_SEPOLIA_OPUS_TROVES_VALIDATOR_ADDRESS as
      | `0x${string}`
      | undefined,
    zkPassportValidatorAddress: import.meta.env
      .VITE_SEPOLIA_ZK_PASSPORT_VALIDATOR_ADDRESS as
      | `0x${string}`
      | undefined,
    merkleValidatorAddress: (
      import.meta.env.VITE_SEPOLIA_MERKLE_VALIDATOR_ADDRESS ||
      "0x048a24bb277dd9659997b92b18aea10c209713f817a549a5154c63677de6ea14"
    ) as `0x${string}`,
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
