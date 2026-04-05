import { Vote } from "lucide-react";
import { useChainConfig } from "@/contexts/NetworkContext";
import { GOVERNANCE_VALIDATOR_ABI } from "@/utils/contracts";
import { EligibilityChecker } from "@/components/EligibilityChecker";
import { PageHeader } from "@/components/PageHeader";
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
    <div className="max-w-3xl mx-auto space-y-6">
      <PageHeader
        title="Governance validator"
        description="Entry validation based on governance participation and voting power"
        icon={Vote}
        contractAddress={validatorAddress}
      />

      {!validatorAddress ? (
        <div className="text-sm text-muted-foreground bg-muted/50 rounded-lg p-4">
          This validator is not deployed on the current network.
        </div>
      ) : (
        <>
          <Card>
            <CardHeader>
              <CardTitle className="text-sm font-medium">Configuration</CardTitle>
              <CardDescription>
                Config is set per-context by the owner. Includes governor address,
                token, threshold, proposal ID, vote checks, and votes per entry.
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
