import { useState } from "react";
import { useReadContract } from "@starknet-react/core";
import { useChainConfig } from "@/contexts/NetworkContext";
import { TOURNAMENT_VALIDATOR_ABI } from "@/utils/contracts";
import { ValidatorConfigCard } from "@/components/ValidatorConfigCard";
import { EligibilityChecker } from "@/components/EligibilityChecker";
import { PageHeader } from "@/components/PageHeader";
import { Trophy } from "lucide-react";

export function TournamentValidatorPage() {
  const { chainConfig } = useChainConfig();
  const validatorAddress = chainConfig.tournamentValidatorAddress;
  const [contextId, setContextId] = useState("");

  const queryArgs = contextId ? [BigInt(contextId)] : undefined;

  const { data: qualifierType, isLoading: l1 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: TOURNAMENT_VALIDATOR_ABI,
    functionName: "get_qualifier_type",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const { data: qualifyingMode, isLoading: l2 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: TOURNAMENT_VALIDATOR_ABI,
    functionName: "get_qualifying_mode",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const { data: qualifyingTournamentIds, isLoading: l3 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: TOURNAMENT_VALIDATOR_ABI,
    functionName: "get_qualifying_tournament_ids",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const { data: topPositions, isLoading: l4 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: TOURNAMENT_VALIDATOR_ABI,
    functionName: "get_top_positions",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const isLoading = l1 || l2 || l3 || l4;
  const hasData = qualifierType !== undefined;

  const qualifierTypeLabel =
    qualifierType !== undefined
      ? String(qualifierType) === "0"
        ? "Participants"
        : "Top Position"
      : "-";

  const qualifyingModeLabel =
    qualifyingMode !== undefined
      ? String(qualifyingMode) === "0"
        ? "Per Token"
        : "All"
      : "-";

  const topPositionsLabel =
    topPositions !== undefined
      ? Number(topPositions) === 0
        ? "All positions"
        : String(topPositions)
      : "-";

  // Format qualifying tournament IDs array
  const tournamentIdsDisplay = qualifyingTournamentIds
    ? Array.isArray(qualifyingTournamentIds)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ? (qualifyingTournamentIds as any[]).map(String).join(", ")
      : String(qualifyingTournamentIds)
    : "-";

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <PageHeader
        title="Tournament validator"
        description="Entry validation based on participation or placement in prior tournaments"
        icon={Trophy}
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
            description="View qualification requirements for a context"
            contextId={contextId}
            onContextIdChange={setContextId}
            isLoading={isLoading}
            hasData={!!hasData}
          >
            <div className="grid grid-cols-2 gap-3">
              <div>
                <p className="text-sm text-muted-foreground">Qualifier Type</p>
                <p className="text-sm font-semibold">{qualifierTypeLabel}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">
                  Qualifying Mode
                </p>
                <p className="text-sm font-semibold">{qualifyingModeLabel}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Top Positions</p>
                <p className="text-sm font-semibold">{topPositionsLabel}</p>
              </div>
              <div className="col-span-2">
                <p className="text-sm text-muted-foreground">
                  Qualifying Tournament IDs
                </p>
                <p className="text-sm font-mono">{tournamentIdsDisplay}</p>
              </div>
            </div>
          </ValidatorConfigCard>

          <EligibilityChecker
            validatorAddress={validatorAddress}
            abi={TOURNAMENT_VALIDATOR_ABI}
            qualificationFields={[
              {
                name: "Qualifying Tournament ID",
                placeholder: "e.g. 1",
              },
              { name: "Token ID", placeholder: "e.g. 1" },
            ]}
          />
        </>
      )}
    </div>
  );
}
