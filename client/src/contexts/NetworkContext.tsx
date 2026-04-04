import { createContext, useContext, type ReactNode, useMemo } from "react";
import { useNetwork } from "@starknet-react/core";
import {
  type ChainId,
  type ChainConfig,
  getDefaultChainId,
  getNetworkConfig,
} from "../networks";

interface NetworkContextValue {
  chainConfig: ChainConfig;
  chainId: ChainId;
  isMainnet: boolean;
  isSepolia: boolean;
}

const NetworkContext = createContext<NetworkContextValue | null>(null);

function feltToShortString(felt: bigint): string {
  let hex = felt.toString(16);
  if (hex.length % 2 !== 0) hex = "0" + hex;
  let result = "";
  for (let i = 0; i < hex.length; i += 2) {
    result += String.fromCharCode(parseInt(hex.substring(i, i + 2), 16));
  }
  return result;
}

export function NetworkProvider({ children }: { children: ReactNode }) {
  const { chain } = useNetwork();

  const value = useMemo(() => {
    // URL param takes precedence so shared links work regardless of wallet state
    const urlChainId = getDefaultChainId();
    const urlParams = new URLSearchParams(window.location.search);
    const hasUrlParam = urlParams.has("network");

    let chainId: ChainId;
    if (hasUrlParam) {
      chainId = urlChainId;
    } else if (chain?.id) {
      const name = feltToShortString(chain.id);
      chainId = name === "SN_SEPOLIA" ? "SN_SEPOLIA" : "SN_MAIN";
    } else {
      chainId = urlChainId;
    }

    const chainConfig = getNetworkConfig(chainId);
    return {
      chainConfig,
      chainId,
      isMainnet: chainId === "SN_MAIN",
      isSepolia: chainId === "SN_SEPOLIA",
    };
  }, [chain?.id]);

  return (
    <NetworkContext.Provider value={value}>{children}</NetworkContext.Provider>
  );
}

export function useChainConfig(): NetworkContextValue {
  const ctx = useContext(NetworkContext);
  if (!ctx)
    throw new Error("useChainConfig must be used within NetworkProvider");
  return ctx;
}
