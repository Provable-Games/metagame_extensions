import { useState, useEffect } from "react";
import { useAccount, useReadContract } from "@starknet-react/core";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { CheckCircle, XCircle, Search } from "lucide-react";

interface QualificationField {
  name: string;
  placeholder: string;
}

interface EligibilityCheckerProps {
  validatorAddress?: string;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  abi: readonly any[];
  qualificationFields?: QualificationField[];
}

export function EligibilityChecker({
  validatorAddress,
  abi,
  qualificationFields = [],
}: EligibilityCheckerProps) {
  const { address: connectedAddress } = useAccount();
  const [contextId, setContextId] = useState("");
  const [playerAddress, setPlayerAddress] = useState("");
  const [qualificationValues, setQualificationValues] = useState<string[]>(
    qualificationFields.map(() => "")
  );
  const [checked, setChecked] = useState(false);

  useEffect(() => {
    if (connectedAddress && !playerAddress) {
      setPlayerAddress(connectedAddress);
    }
  }, [connectedAddress, playerAddress]);

  const qualification = qualificationValues.filter((v) => v !== "");

  const shouldQuery = checked && contextId && playerAddress && validatorAddress;

  const { data: validEntryData, isLoading: isLoadingValid } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi,
    functionName: "valid_entry",
    args: shouldQuery ? [BigInt(contextId), playerAddress, qualification] : undefined,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const { data: entriesLeftData, isLoading: isLoadingEntries } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi,
    functionName: "entries_left",
    args: shouldQuery ? [BigInt(contextId), playerAddress, qualification] : undefined,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const handleCheck = () => {
    setChecked(true);
  };

  const isLoading = isLoadingValid || isLoadingEntries;

  // Parse the boolean result from Cairo enum
  const isEligible = validEntryData !== undefined
    ? typeof validEntryData === "boolean"
      ? validEntryData
      : typeof validEntryData === "object" && validEntryData !== null
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        ? "True" in (validEntryData as any) || (validEntryData as any).variant === "True"
        : false
    : undefined;

  // Parse entries_left Option<u8>
  const entriesLeft = entriesLeftData !== undefined
    ? typeof entriesLeftData === "object" && entriesLeftData !== null
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ? "Some" in (entriesLeftData as any)
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        ? Number((entriesLeftData as any).Some)
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        : "None" in (entriesLeftData as any)
          ? null // None = unlimited
          : typeof entriesLeftData === "number" ? entriesLeftData : undefined
      : typeof entriesLeftData === "number"
        ? entriesLeftData
        : undefined
    : undefined;

  return (
    <Card>
      <CardHeader>
        <CardTitle>Check Eligibility</CardTitle>
        <CardDescription>
          Check if a player is eligible for a context with this validator
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {!validatorAddress && (
          <div className="text-sm text-muted-foreground bg-muted rounded-md p-3">
            This validator is not deployed on the current network.
          </div>
        )}

        <div>
          <Label htmlFor="elig-context-id">Context ID</Label>
          <Input
            id="elig-context-id"
            type="number"
            placeholder="Enter context ID"
            value={contextId}
            onChange={(e) => { setContextId(e.target.value); setChecked(false); }}
            disabled={!validatorAddress}
          />
        </div>

        <div>
          <Label htmlFor="elig-player-address">Player Address</Label>
          <Input
            id="elig-player-address"
            placeholder="0x..."
            value={playerAddress}
            onChange={(e) => { setPlayerAddress(e.target.value); setChecked(false); }}
            disabled={!validatorAddress}
          />
        </div>

        {qualificationFields.map((field, index) => (
          <div key={field.name}>
            <Label htmlFor={`qual-${field.name}`}>{field.name}</Label>
            <Input
              id={`qual-${field.name}`}
              placeholder={field.placeholder}
              value={qualificationValues[index]}
              onChange={(e) => {
                const newValues = [...qualificationValues];
                newValues[index] = e.target.value;
                setQualificationValues(newValues);
                setChecked(false);
              }}
              disabled={!validatorAddress}
            />
          </div>
        ))}

        <Button
          onClick={handleCheck}
          disabled={!validatorAddress || !contextId || !playerAddress}
          className="w-full"
        >
          <Search className="h-4 w-4 mr-2" />
          Check Eligibility
        </Button>

        {checked && shouldQuery && !isLoading && isEligible !== undefined && (
          <div className="bg-muted rounded-md p-4 space-y-2">
            <div className="flex items-center gap-2">
              {isEligible ? (
                <>
                  <CheckCircle className="h-5 w-5 text-green-500" />
                  <span className="font-semibold text-green-600 dark:text-green-400">Eligible</span>
                </>
              ) : (
                <>
                  <XCircle className="h-5 w-5 text-red-500" />
                  <span className="font-semibold text-red-600 dark:text-red-400">Not Eligible</span>
                </>
              )}
            </div>
            {entriesLeft !== undefined && (
              <p className="text-sm text-muted-foreground">
                Entries remaining: {entriesLeft === null ? "Unlimited" : entriesLeft}
              </p>
            )}
          </div>
        )}

        {checked && isLoading && (
          <div className="text-center text-muted-foreground py-2">Checking...</div>
        )}
      </CardContent>
    </Card>
  );
}
