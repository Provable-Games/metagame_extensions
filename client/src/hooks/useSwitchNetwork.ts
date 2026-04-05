import { useCallback } from "react";
import { useSwitchChain } from "@starknet-react/core";
import { CHAIN_ID_FELTS } from "../networks";

function setNetworkParam(network: string) {
  const url = new URL(window.location.href);
  url.searchParams.set("network", network);
  window.history.replaceState({}, "", url.toString());
}

export function useSwitchNetwork() {
  const { switchChain, switchChainAsync } = useSwitchChain({});

  const switchToMainnet = useCallback(() => {
    switchChain({ chainId: CHAIN_ID_FELTS.SN_MAIN });
    setNetworkParam("mainnet");
  }, [switchChain]);

  const switchToSepolia = useCallback(() => {
    switchChain({ chainId: CHAIN_ID_FELTS.SN_SEPOLIA });
    setNetworkParam("sepolia");
  }, [switchChain]);

  return { switchToMainnet, switchToSepolia, switchChain, switchChainAsync };
}
