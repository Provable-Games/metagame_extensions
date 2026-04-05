import { useState } from "react";
import { useReadContract } from "@starknet-react/core";
import { useChainConfig } from "@/contexts/NetworkContext";
import { OPUS_TROVES_VALIDATOR_ABI } from "@/utils/contracts";
import { ValidatorConfigCard } from "@/components/ValidatorConfigCard";
import { EligibilityChecker } from "@/components/EligibilityChecker";

export function OpusTrovesValidatorPage() {
  const { chainConfig } = useChainConfig();
  const validatorAddress = chainConfig.opusTrovesValidatorAddress;
  const [contextId, setContextId] = useState("");

  const queryArgs = contextId ? [BigInt(contextId)] : undefined;

  const { data: debtThreshold, isLoading: l1 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: OPUS_TROVES_VALIDATOR_ABI,
    functionName: "get_debt_threshold",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const { data: valuePerEntry, isLoading: l2 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: OPUS_TROVES_VALIDATOR_ABI,
    functionName: "get_value_per_entry",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const { data: maxEntries, isLoading: l3 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: OPUS_TROVES_VALIDATOR_ABI,
    functionName: "get_max_entries",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const isLoading = l1 || l2 || l3;
  const hasData = debtThreshold !== undefined;

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Opus Troves Validator</h1>
        <p className="text-muted-foreground mt-2">
          Entry validation based on Opus Protocol debt positions
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
            description="View Opus Troves debt requirements for a context"
            contextId={contextId}
            onContextIdChange={setContextId}
            isLoading={isLoading}
            hasData={!!hasData}
          >
            <div className="grid grid-cols-2 gap-3">
              <div>
                <p className="text-sm text-muted-foreground">
                  Debt Threshold (WAD)
                </p>
                <p className="text-sm font-mono">
                  {debtThreshold !== undefined ? String(debtThreshold) : "-"}
                </p>
                <p className="text-xs text-muted-foreground">1e18 = 1 yin</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Max Entries</p>
                <p className="text-sm font-semibold">
                  {maxEntries !== undefined ? String(maxEntries) : "-"}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">
                  Value Per Entry (WAD)
                </p>
                <p className="text-sm font-mono">
                  {valuePerEntry !== undefined ? String(valuePerEntry) : "-"}
                </p>
              </div>
            </div>
          </ValidatorConfigCard>

          <EligibilityChecker
            validatorAddress={validatorAddress}
            abi={OPUS_TROVES_VALIDATOR_ABI}
          />
        </>
      )}
    </div>
  );
}
