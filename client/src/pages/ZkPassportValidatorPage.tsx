import { useState } from "react";
import { useReadContract } from "@starknet-react/core";
import { useChainConfig } from "@/contexts/NetworkContext";
import { ZK_PASSPORT_VALIDATOR_ABI } from "@/utils/contracts";
import { ValidatorConfigCard } from "@/components/ValidatorConfigCard";
import { EligibilityChecker } from "@/components/EligibilityChecker";
import { AddressDisplay } from "@/components/AddressDisplay";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Search, CheckCircle, XCircle, ShieldCheck } from "lucide-react";
import { PageHeader } from "@/components/PageHeader";

export function ZkPassportValidatorPage() {
  const { chainConfig } = useChainConfig();
  const validatorAddress = chainConfig.zkPassportValidatorAddress;
  const [contextId, setContextId] = useState("");

  // Nullifier lookup state
  const [nullifierContextId, setNullifierContextId] = useState("");
  const [nullifierHash, setNullifierHash] = useState("");
  const [checkNullifier, setCheckNullifier] = useState(false);

  const queryArgs = contextId ? [BigInt(contextId)] : undefined;

  const { data: verifierAddress, isLoading: l1 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: ZK_PASSPORT_VALIDATOR_ABI,
    functionName: "get_verifier_address",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const { data: serviceScope, isLoading: l2 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: ZK_PASSPORT_VALIDATOR_ABI,
    functionName: "get_expected_service_scope",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const { data: serviceSubscope, isLoading: l3 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: ZK_PASSPORT_VALIDATOR_ABI,
    functionName: "get_expected_service_subscope",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const { data: paramCommitment, isLoading: l4 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: ZK_PASSPORT_VALIDATOR_ABI,
    functionName: "get_expected_param_commitment",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const { data: maxProofAge, isLoading: l5 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: ZK_PASSPORT_VALIDATOR_ABI,
    functionName: "get_max_proof_age",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const { data: nullifierType, isLoading: l6 } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: ZK_PASSPORT_VALIDATOR_ABI,
    functionName: "get_expected_nullifier_type",
    args: queryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  // Nullifier check
  const nullifierQueryArgs =
    checkNullifier && nullifierContextId && nullifierHash
      ? [BigInt(nullifierContextId), nullifierHash]
      : undefined;

  const { data: nullifierUsed, isLoading: nullifierLoading } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: ZK_PASSPORT_VALIDATOR_ABI,
    functionName: "is_nullifier_used",
    args: nullifierQueryArgs,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const isLoading = l1 || l2 || l3 || l4 || l5 || l6;
  const hasData = verifierAddress !== undefined;

  // Parse nullifier result
  const isNullifierUsed =
    nullifierUsed !== undefined
      ? typeof nullifierUsed === "boolean"
        ? nullifierUsed
        : typeof nullifierUsed === "object" &&
          nullifierUsed !== null &&
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          "True" in (nullifierUsed as any)
      : undefined;

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <PageHeader
        title="ZK Passport validator"
        description="Entry via zero-knowledge passport proof with sybil prevention"
        icon={ShieldCheck}
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
            description="View ZK Passport verification requirements for a context"
            contextId={contextId}
            onContextIdChange={setContextId}
            isLoading={isLoading}
            hasData={!!hasData}
          >
            <div className="grid grid-cols-2 gap-3">
              <div>
                <p className="text-sm text-muted-foreground">
                  Verifier Address
                </p>
                {verifierAddress ? (
                  <AddressDisplay address={String(verifierAddress)} />
                ) : (
                  <p className="text-sm">-</p>
                )}
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Max Proof Age</p>
                <p className="text-sm font-semibold">
                  {maxProofAge !== undefined ? `${String(maxProofAge)}s` : "-"}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Service Scope</p>
                <p
                  className="text-sm font-mono truncate"
                  title={
                    serviceScope !== undefined ? String(serviceScope) : ""
                  }
                >
                  {serviceScope !== undefined ? String(serviceScope) : "-"}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">
                  Service Subscope
                </p>
                <p
                  className="text-sm font-mono truncate"
                  title={
                    serviceSubscope !== undefined
                      ? String(serviceSubscope)
                      : ""
                  }
                >
                  {serviceSubscope !== undefined
                    ? String(serviceSubscope)
                    : "-"}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">
                  Param Commitment
                </p>
                <p
                  className="text-sm font-mono truncate"
                  title={
                    paramCommitment !== undefined
                      ? String(paramCommitment)
                      : ""
                  }
                >
                  {paramCommitment !== undefined
                    ? String(paramCommitment)
                    : "-"}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Nullifier Type</p>
                <p
                  className="text-sm font-mono truncate"
                  title={
                    nullifierType !== undefined ? String(nullifierType) : ""
                  }
                >
                  {nullifierType !== undefined ? String(nullifierType) : "-"}
                </p>
              </div>
            </div>
          </ValidatorConfigCard>

          {/* Nullifier Lookup */}
          <Card>
            <CardHeader>
              <CardTitle>Nullifier Lookup</CardTitle>
              <CardDescription>
                Check if a nullifier has been used for a context
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <Label htmlFor="null-context-id">Context ID</Label>
                <Input
                  id="null-context-id"
                  type="number"
                  placeholder="Enter context ID"
                  value={nullifierContextId}
                  onChange={(e) => {
                    setNullifierContextId(e.target.value);
                    setCheckNullifier(false);
                  }}
                />
              </div>
              <div>
                <Label htmlFor="null-hash">Nullifier Hash</Label>
                <Input
                  id="null-hash"
                  placeholder="0x..."
                  value={nullifierHash}
                  onChange={(e) => {
                    setNullifierHash(e.target.value);
                    setCheckNullifier(false);
                  }}
                />
              </div>
              <Button
                onClick={() => setCheckNullifier(true)}
                disabled={!nullifierContextId || !nullifierHash}
                className="w-full"
              >
                <Search className="h-4 w-4 mr-2" />
                Check Nullifier
              </Button>

              {checkNullifier &&
                !nullifierLoading &&
                isNullifierUsed !== undefined && (
                  <div className="bg-muted rounded-md p-4 flex items-center gap-2">
                    {isNullifierUsed ? (
                      <>
                        <XCircle className="h-5 w-5 text-red-500" />
                        <span className="font-semibold text-red-600 dark:text-red-400">
                          Nullifier already used
                        </span>
                      </>
                    ) : (
                      <>
                        <CheckCircle className="h-5 w-5 text-green-500" />
                        <span className="font-semibold text-green-600 dark:text-green-400">
                          Nullifier available
                        </span>
                      </>
                    )}
                  </div>
                )}

              {checkNullifier && nullifierLoading && (
                <div className="text-center text-muted-foreground py-2">
                  Checking...
                </div>
              )}
            </CardContent>
          </Card>

          <EligibilityChecker
            validatorAddress={validatorAddress}
            abi={ZK_PASSPORT_VALIDATOR_ABI}
            qualificationFields={[
              {
                name: "Qualification Data (felt252)",
                placeholder: "Raw felt252 value",
              },
            ]}
          />
        </>
      )}
    </div>
  );
}
