import { type ReactNode, useMemo } from "react";
import {
  StarknetConfig,
  jsonRpcProvider,
  voyager,
  InjectedConnector,
} from "@starknet-react/core";
import { ControllerConnector } from "@cartridge/connector";
import {
  getDefaultChainId,
  getNetworkConfig,
  getAllChains,
  CHAIN_ID_FELTS,
} from "../networks";

const defaultChainId = getDefaultChainId();
const mainnetConfig = getNetworkConfig("SN_MAIN");
const sepoliaConfig = getNetworkConfig("SN_SEPOLIA");
const chains = getAllChains();

const orderedChains =
  defaultChainId === "SN_SEPOLIA"
    ? ([chains[1], chains[0]] as const)
    : ([chains[0], chains[1]] as const);

const snapshotMethods = [
  { name: "create_snapshot", entrypoint: "create_snapshot" },
  { name: "upload_snapshot_data", entrypoint: "upload_snapshot_data" },
  { name: "lock_snapshot", entrypoint: "lock_snapshot" },
];

const merkleMethods = [
  { name: "create_tree", entrypoint: "create_tree" },
];

function buildPolicies() {
  const contracts: Record<
    string,
    { methods: { name: string; entrypoint: string }[] }
  > = {};
  if (mainnetConfig.snapshotValidatorAddress) {
    contracts[mainnetConfig.snapshotValidatorAddress] = {
      methods: snapshotMethods,
    };
  }
  if (sepoliaConfig.snapshotValidatorAddress) {
    contracts[sepoliaConfig.snapshotValidatorAddress] = {
      methods: snapshotMethods,
    };
  }
  if (mainnetConfig.merkleValidatorAddress) {
    contracts[mainnetConfig.merkleValidatorAddress] = {
      methods: merkleMethods,
    };
  }
  if (sepoliaConfig.merkleValidatorAddress) {
    contracts[sepoliaConfig.merkleValidatorAddress] = {
      methods: merkleMethods,
    };
  }
  return contracts;
}

const cartridgeConnector =
  typeof window !== "undefined"
    ? new ControllerConnector({
        chains: [
          { rpcUrl: mainnetConfig.rpcUrl },
          { rpcUrl: sepoliaConfig.rpcUrl },
        ],
        defaultChainId: CHAIN_ID_FELTS[defaultChainId],
        policies: {
          contracts: buildPolicies(),
        },
      })
    : null;

const argentConnector = new InjectedConnector({
  options: { id: "argentX", name: "Argent X" },
});

const braavosConnector = new InjectedConnector({
  options: { id: "braavos", name: "Braavos" },
});

const rpcByChainId: Record<string, string> = {
  [String(chains[0].id)]: mainnetConfig.rpcUrl,
  [String(chains[1].id)]: sepoliaConfig.rpcUrl,
};

export function StarknetProvider({ children }: { children: ReactNode }) {
  const connectors = useMemo(() => {
    const base: any[] = [];
    if (cartridgeConnector) {
      base.push(cartridgeConnector);
    }
    base.push(argentConnector, braavosConnector);
    return base;
  }, []);

  const rpc = useMemo(
    () => (chain: { id: bigint }) => ({
      nodeUrl: rpcByChainId[String(chain.id)] || mainnetConfig.rpcUrl,
    }),
    [],
  );

  return (
    <StarknetConfig
      chains={[...orderedChains]}
      provider={jsonRpcProvider({ rpc })}
      connectors={connectors}
      explorer={voyager}
      autoConnect
    >
      {children}
    </StarknetConfig>
  );
}
