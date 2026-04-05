import { useState, useEffect } from "react";
import { useAccount, useReadContract } from "@starknet-react/core";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { CheckCircle, XCircle, Search, Loader2 } from "lucide-react";

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

  const isEligible = validEntryData !== undefined
    ? typeof validEntryData === "boolean"
      ? validEntryData
      : typeof validEntryData === "object" && validEntryData !== null
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        ? "True" in (validEntryData as any) || (validEntryData as any).variant === "True"
        : false
    : undefined;

  const entriesLeft = entriesLeftData !== undefined
    ? typeof entriesLeftData === "object" && entriesLeftData !== null
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ? "Some" in (entriesLeftData as any)
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        ? Number((entriesLeftData as any).Some)
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        : "None" in (entriesLeftData as any)
          ? null
          : typeof entriesLeftData === "number" ? entriesLeftData : undefined
      : typeof entriesLeftData === "number"
        ? entriesLeftData
        : undefined
    : undefined;

  return (
    <div className="rounded-xl border border-border/60 bg-card">
      <div className="p-5 pb-0">
        <h3 className="text-sm font-medium">Check eligibility</h3>
        <p className="text-xs text-muted-foreground mt-0.5">
          Verify if a player meets the entry requirements for a context
        </p>
      </div>
      <div className="p-5 space-y-4">
        {!validatorAddress && (
          <div className="text-sm text-muted-foreground bg-muted/50 rounded-lg p-3">
            This validator is not deployed on the current network.
          </div>
        )}

        <div>
          <Label htmlFor="elig-context-id" className="text-xs">Context ID</Label>
          <Input
            id="elig-context-id"
            type="number"
            placeholder="Enter context ID"
            value={contextId}
            onChange={(e) => { setContextId(e.target.value); setChecked(false); }}
            disabled={!validatorAddress}
            className="mt-1.5"
          />
        </div>

        <div>
          <Label htmlFor="elig-player-address" className="text-xs">Player address</Label>
          <Input
            id="elig-player-address"
            placeholder="0x..."
            value={playerAddress}
            onChange={(e) => { setPlayerAddress(e.target.value); setChecked(false); }}
            disabled={!validatorAddress}
            className="mt-1.5"
          />
        </div>

        {qualificationFields.map((field, index) => (
          <div key={field.name}>
            <Label htmlFor={`qual-${field.name}`} className="text-xs">{field.name}</Label>
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
              className="mt-1.5"
            />
          </div>
        ))}

        <Button
          onClick={handleCheck}
          disabled={!validatorAddress || !contextId || !playerAddress}
          className="w-full"
          size="sm"
        >
          <Search className="h-3.5 w-3.5 mr-1.5" />
          Check eligibility
        </Button>

        {checked && isLoading && (
          <div className="flex items-center justify-center text-muted-foreground py-4">
            <Loader2 className="h-4 w-4 animate-spin mr-2" />
            <span className="text-xs">Checking...</span>
          </div>
        )}

        {checked && shouldQuery && !isLoading && isEligible !== undefined && (
          <div className={`rounded-lg p-4 ${
            isEligible
              ? "bg-emerald-500/10 border border-emerald-500/20"
              : "bg-destructive/10 border border-destructive/20"
          }`}>
            <div className="flex items-center gap-2">
              {isEligible ? (
                <>
                  <CheckCircle className="h-4 w-4 text-emerald-500" />
                  <span className="text-sm font-medium text-emerald-600 dark:text-emerald-400">Eligible</span>
                </>
              ) : (
                <>
                  <XCircle className="h-4 w-4 text-destructive" />
                  <span className="text-sm font-medium text-destructive">Not eligible</span>
                </>
              )}
            </div>
            {entriesLeft !== undefined && (
              <p className="text-xs text-muted-foreground mt-1.5 ml-6">
                Entries remaining: {entriesLeft === null ? "Unlimited" : entriesLeft}
              </p>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
