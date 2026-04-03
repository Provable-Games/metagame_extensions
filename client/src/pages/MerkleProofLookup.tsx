import { useState } from "react";
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
import {
  Search,
  Upload,
  Copy,
  Check,
  CheckCircle,
  XCircle,
} from "lucide-react";
import {
  findEntry,
  getProof,
  buildQualification,
  type MerkleTreeData,
} from "@/utils/merkleTree";
import { MERKLE_VALIDATOR_ABI } from "@/utils/contracts";
import { useChainConfig } from "@/contexts/NetworkContext";
import { useReadContract } from "@starknet-react/core";

export function MerkleProofLookup() {
  const { chainConfig } = useChainConfig();
  const validatorAddress = chainConfig.merkleValidatorAddress;

  const [treeData, setTreeData] = useState<MerkleTreeData | null>(null);
  const [lookupAddress, setLookupAddress] = useState("");
  const [proofResult, setProofResult] = useState<{
    count: number;
    proof: string[];
    qualification: string[];
  } | null>(null);
  const [error, setError] = useState("");
  const [copied, setCopied] = useState(false);
  const [verifyContextId, setVerifyContextId] = useState("");

  const shouldVerify =
    verifyContextId && validatorAddress && proofResult && treeData;

  const { data: onChainRoot, isLoading: isVerifying } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: MERKLE_VALIDATOR_ABI,
    functionName: "get_merkle_root",
    args: shouldVerify ? [BigInt(verifyContextId)] : undefined,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const rootsMatch =
    onChainRoot !== undefined && treeData
      ? String(onChainRoot) === treeData.root
      : undefined;

  const handleFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (event) => {
      try {
        const data = JSON.parse(
          event.target?.result as string
        ) as MerkleTreeData;
        if (!data.root || !data.leaves || !data.entries) {
          setError(
            "Invalid merkle tree file: missing root, leaves, or entries"
          );
          return;
        }
        setTreeData(data);
        setError("");
        setProofResult(null);
      } catch {
        setError("Invalid JSON file");
      }
    };
    reader.readAsText(file);
  };

  const handleLookup = () => {
    if (!treeData || !lookupAddress) return;
    setError("");

    const entry = findEntry(treeData, lookupAddress);
    if (!entry) {
      setError("Address not found in tree");
      setProofResult(null);
      return;
    }

    const proof = getProof(treeData, entry.address, entry.count);
    if (!proof) {
      setError("Could not generate proof");
      setProofResult(null);
      return;
    }

    const qualification = buildQualification(entry.count, proof);
    setProofResult({ count: entry.count, proof, qualification });
  };

  const handleCopyQualification = async () => {
    if (!proofResult) return;
    const text = JSON.stringify(proofResult.qualification);
    await navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Merkle Proof Lookup</h1>
        <p className="text-muted-foreground mt-2">
          Upload a merkle tree file and look up proofs for individual addresses
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Load Merkle Tree</CardTitle>
          <CardDescription>
            Upload a merkle tree JSON file generated from the Create Merkle Tree
            page
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div>
            <Label htmlFor="tree-file">Tree Data File</Label>
            <Input
              id="tree-file"
              type="file"
              accept=".json"
              onChange={handleFileUpload}
            />
          </div>

          {error && !treeData && (
            <div className="text-sm text-destructive bg-destructive/10 rounded-md p-3">
              {error}
            </div>
          )}

          {treeData && (
            <div className="bg-muted rounded-md p-4 space-y-2">
              <div className="flex items-center gap-2">
                <Upload className="h-4 w-4 text-muted-foreground" />
                <span className="text-sm font-semibold">Tree Loaded</span>
              </div>
              <div className="grid grid-cols-2 gap-2 text-sm">
                <div>
                  <span className="text-muted-foreground">Root: </span>
                  <span className="font-mono break-all">
                    {treeData.root.slice(0, 20)}...
                  </span>
                </div>
                <div>
                  <span className="text-muted-foreground">Entries: </span>
                  <span className="font-semibold">
                    {treeData.entries.length}
                  </span>
                </div>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {treeData && (
        <Card>
          <CardHeader>
            <CardTitle>Lookup Address</CardTitle>
            <CardDescription>
              Enter an address to find its entry count and generate a merkle
              proof
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div>
              <Label htmlFor="lookup-address">Player Address</Label>
              <Input
                id="lookup-address"
                placeholder="0x..."
                value={lookupAddress}
                onChange={(e) => {
                  setLookupAddress(e.target.value);
                  setProofResult(null);
                  setError("");
                }}
              />
            </div>

            <Button
              onClick={handleLookup}
              disabled={!lookupAddress}
              className="w-full"
            >
              <Search className="h-4 w-4 mr-2" />
              Lookup Proof
            </Button>

            {error && proofResult === null && (
              <div className="text-sm text-destructive bg-destructive/10 rounded-md p-3">
                {error}
              </div>
            )}

            {proofResult && (
              <div className="space-y-4">
                <div className="bg-muted rounded-md p-4 space-y-3">
                  <div>
                    <p className="text-sm text-muted-foreground">Entry Count</p>
                    <p className="text-sm font-semibold">{proofResult.count}</p>
                  </div>
                  <div>
                    <p className="text-sm text-muted-foreground">
                      Proof Elements ({proofResult.proof.length})
                    </p>
                    <div className="max-h-32 overflow-y-auto space-y-1 mt-1">
                      {proofResult.proof.map((element, i) => (
                        <p key={i} className="text-xs font-mono break-all">
                          [{i}] {element}
                        </p>
                      ))}
                    </div>
                  </div>
                </div>

                <div>
                  <div className="flex items-center justify-between mb-2">
                    <p className="text-sm font-semibold">Qualification Array</p>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={handleCopyQualification}
                    >
                      {copied ? (
                        <Check className="h-4 w-4 text-green-500" />
                      ) : (
                        <Copy className="h-4 w-4" />
                      )}
                      <span className="ml-1">
                        {copied ? "Copied" : "Copy"}
                      </span>
                    </Button>
                  </div>
                  <div className="bg-muted rounded-md p-3 font-mono text-xs break-all max-h-48 overflow-y-auto">
                    {JSON.stringify(proofResult.qualification, null, 2)}
                  </div>
                  <p className="text-xs text-muted-foreground mt-2">
                    Format: [entry_count, ...proof_elements]. Use this as the
                    qualification parameter when calling validate_entry or
                    entries_left.
                  </p>
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {proofResult && validatorAddress && (
        <Card>
          <CardHeader>
            <CardTitle>Verify Against On-Chain Root</CardTitle>
            <CardDescription>
              Optionally verify that the tree root matches the on-chain
              configuration for a context
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div>
              <Label htmlFor="verify-context-id">Context ID</Label>
              <Input
                id="verify-context-id"
                type="number"
                placeholder="Enter context ID"
                value={verifyContextId}
                onChange={(e) => setVerifyContextId(e.target.value)}
              />
            </div>

            {isVerifying && (
              <div className="text-center text-muted-foreground py-2">
                Verifying...
              </div>
            )}

            {verifyContextId && rootsMatch !== undefined && !isVerifying && (
              <div className="bg-muted rounded-md p-4">
                <div className="flex items-center gap-2">
                  {rootsMatch ? (
                    <>
                      <CheckCircle className="h-5 w-5 text-green-500" />
                      <span className="font-semibold text-green-600 dark:text-green-400">
                        Roots Match
                      </span>
                    </>
                  ) : (
                    <>
                      <XCircle className="h-5 w-5 text-red-500" />
                      <span className="font-semibold text-red-600 dark:text-red-400">
                        Roots Do Not Match
                      </span>
                    </>
                  )}
                </div>
                <div className="mt-2 space-y-1 text-xs font-mono">
                  <p>
                    <span className="text-muted-foreground">Tree root: </span>
                    {treeData?.root}
                  </p>
                  <p>
                    <span className="text-muted-foreground">On-chain: </span>
                    {String(onChainRoot)}
                  </p>
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  );
}
