import { useState } from "react";
import { useReadContract } from "@starknet-react/core";
import { Coins } from "lucide-react";
import { useChainConfig } from "@/contexts/NetworkContext";
import { ERC20_BALANCE_VALIDATOR_ABI } from "@/utils/contracts";
import { ValidatorConfigCard } from "@/components/ValidatorConfigCard";
import { EligibilityChecker } from "@/components/EligibilityChecker";
import { AddressDisplay } from "@/components/AddressDisplay";
import { PageHeader } from "@/components/PageHeader";

export function ERC20BalanceValidatorPage() {
  const { chainConfig } = useChainConfig();
  const validatorAddress = chainConfig.erc20BalanceValidatorAddress;
  const [contextId, setContextId] = useState("");

  const queryArgs = contextId ? [BigInt(contextId)] : undefined;

  const { data: tokenAddress, isLoading: l1 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: ERC20_BALANCE_VALIDATOR_ABI,
    functionName: "get_token_address",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const { data: minThreshold, isLoading: l2 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: ERC20_BALANCE_VALIDATOR_ABI,
    functionName: "get_min_threshold",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const { data: maxThreshold, isLoading: l3 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: ERC20_BALANCE_VALIDATOR_ABI,
    functionName: "get_max_threshold",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const { data: valuePerEntry, isLoading: l4 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: ERC20_BALANCE_VALIDATOR_ABI,
    functionName: "get_value_per_entry",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const { data: maxEntries, isLoading: l5 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: ERC20_BALANCE_VALIDATOR_ABI,
    functionName: "get_max_entries",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const isLoading = l1 || l2 || l3 || l4 || l5;
  const hasData = tokenAddress !== undefined;

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <PageHeader
        title="ERC20 Balance validator"
        description="Entry validation based on ERC20 token balance thresholds"
        icon={Coins}
        contractAddress={validatorAddress}
      />

      {!validatorAddress ? (
        <div className="text-sm text-muted-foreground bg-muted/50 rounded-lg p-4">
          This validator is not deployed on the current network.
        </div>
      ) : (
        <>
          <ValidatorConfigCard
            title="Context config"
            description="View the ERC20 balance requirements for a context"
            contextId={contextId}
            onContextIdChange={setContextId}
            isLoading={isLoading}
            hasData={!!hasData}
          >
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-xs text-muted-foreground mb-1">Token address</p>
                {tokenAddress ? (
                  <AddressDisplay address={String(tokenAddress)} />
                ) : (
                  <p className="text-sm text-muted-foreground">-</p>
                )}
              </div>
              <div>
                <p className="text-xs text-muted-foreground mb-1">Max entries</p>
                <p className="text-sm font-medium tabular-nums">
                  {maxEntries !== undefined ? String(maxEntries) : "-"}
                </p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground mb-1">Min threshold</p>
                <p className="text-sm font-mono tabular-nums">
                  {minThreshold !== undefined ? String(minThreshold) : "-"}
                </p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground mb-1">Max threshold</p>
                <p className="text-sm font-mono tabular-nums">
                  {maxThreshold !== undefined ? String(maxThreshold) : "-"}
                </p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground mb-1">Value per entry</p>
                <p className="text-sm font-mono tabular-nums">
                  {valuePerEntry !== undefined ? String(valuePerEntry) : "-"}
                </p>
              </div>
            </div>
          </ValidatorConfigCard>

          <EligibilityChecker
            validatorAddress={validatorAddress}
            abi={ERC20_BALANCE_VALIDATOR_ABI}
          />
        </>
      )}
    </div>
  );
}
