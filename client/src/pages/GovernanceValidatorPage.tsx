import { useChainConfig } from "@/contexts/NetworkContext";
import { GOVERNANCE_VALIDATOR_ABI } from "@/utils/contracts";
import { EligibilityChecker } from "@/components/EligibilityChecker";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export function GovernanceValidatorPage() {
  const { chainConfig } = useChainConfig();
  const validatorAddress = chainConfig.governanceValidatorAddress;

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Governance Validator</h1>
        <p className="text-muted-foreground mt-2">
          Entry validation based on governance participation and voting power
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
          <Card>
            <CardHeader>
              <CardTitle>Configuration</CardTitle>
              <CardDescription>
                Governance validator config is set per-context by the
                context owner. Config includes governor address, token,
                threshold, proposal ID, vote checks, and votes per entry.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <p className="text-sm text-muted-foreground">
                No public config getters are available for this validator. Use
                the eligibility checker below to verify player access.
              </p>
            </CardContent>
          </Card>

          <EligibilityChecker
            validatorAddress={validatorAddress}
            abi={GOVERNANCE_VALIDATOR_ABI}
          />
        </>
      )}
    </div>
  );
}
