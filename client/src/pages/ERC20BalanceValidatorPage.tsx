import { useState } from "react";
import { useReadContract } from "@starknet-react/core";
import { useChainConfig } from "@/contexts/NetworkContext";
import { ERC20_BALANCE_VALIDATOR_ABI } from "@/utils/contracts";
import { ValidatorConfigCard } from "@/components/ValidatorConfigCard";
import { EligibilityChecker } from "@/components/EligibilityChecker";
import { AddressDisplay } from "@/components/AddressDisplay";

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
    <div className="max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-3xl font-bold">ERC20 Balance Validator</h1>
        <p className="text-muted-foreground mt-2">
          Entry validation based on ERC20 token balance thresholds
        </p>
        {validatorAddress && (
          <p className="text-xs text-muted-foreground mt-1 font-mono">
            {validatorAddress}
          </p>
        )}
      </div>

      {!validatorAddress ? (
        <div className="text-sm text-muted-foreground bg-muted rounded-md p-4">
          This validator is not deployed on the current network.
        </div>
      ) : (
        <>
          <ValidatorConfigCard
            title="Context Config"
            description="View the ERC20 balance requirements for a context"
            contextId={contextId}
            onContextIdChange={setContextId}
            isLoading={isLoading}
            hasData={!!hasData}
          >
            <div className="grid grid-cols-2 gap-3">
              <div>
                <p className="text-sm text-muted-foreground">Token Address</p>
                {tokenAddress ? (
                  <AddressDisplay address={String(tokenAddress)} />
                ) : (
                  <p className="text-sm">-</p>
                )}
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Max Entries</p>
                <p className="text-sm font-semibold">
                  {maxEntries !== undefined ? String(maxEntries) : "-"}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Min Threshold</p>
                <p className="text-sm font-mono">
                  {minThreshold !== undefined ? String(minThreshold) : "-"}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Max Threshold</p>
                <p className="text-sm font-mono">
                  {maxThreshold !== undefined ? String(maxThreshold) : "-"}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Value Per Entry</p>
                <p className="text-sm font-mono">
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
