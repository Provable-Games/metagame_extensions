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
import { Search, Copy, Check } from "lucide-react";
import { getMerkleApiUrl } from "@/networks";
import { useChainConfig } from "@/contexts/NetworkContext";

export function MerkleProofLookup() {
  const { chainConfig } = useChainConfig();
  const [treeId, setTreeId] = useState("");
  const [address, setAddress] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [copied, setCopied] = useState(false);
  const [proofResult, setProofResult] = useState<{
    count: number;
    proof: string[];
    qualification: string[];
  } | null>(null);

  const handleLookup = async () => {
    if (!treeId || !address) return;
    setLoading(true);
    setError("");
    setProofResult(null);
    try {
      const res = await fetch(
        `${getMerkleApiUrl(chainConfig.chainId)}/trees/${treeId}/proof/${address.toLowerCase()}`,
      );
      if (!res.ok) {
        const data = await res.json();
        setError(data.error || "Proof not found");
        return;
      }
      const data = await res.json();
      setProofResult({
        count: data.count,
        proof: data.proof,
        qualification: data.qualification,
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : "API request failed");
    } finally {
      setLoading(false);
    }
  };

  const handleCopyQualification = async () => {
    if (!proofResult) return;
    await navigator.clipboard.writeText(
      JSON.stringify(proofResult.qualification),
    );
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Merkle Proof Lookup</h1>
        <p className="text-muted-foreground mt-2">
          Fetch merkle proofs by tree ID and player address
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Lookup Proof</CardTitle>
          <CardDescription>
            Enter the tree ID and player address to fetch the merkle proof
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div>
            <Label htmlFor="tree-id">Tree ID</Label>
            <Input
              id="tree-id"
              type="number"
              placeholder="e.g. 1"
              value={treeId}
              onChange={(e) => {
                setTreeId(e.target.value);
                setProofResult(null);
                setError("");
              }}
            />
          </div>
          <div>
            <Label htmlFor="address">Player Address</Label>
            <Input
              id="address"
              placeholder="0x..."
              value={address}
              onChange={(e) => {
                setAddress(e.target.value);
                setProofResult(null);
                setError("");
              }}
            />
          </div>

          <Button
            onClick={handleLookup}
            disabled={!treeId || !address || loading}
            className="w-full"
          >
            <Search className="h-4 w-4 mr-2" />
            {loading ? "Looking up..." : "Lookup Proof"}
          </Button>

          {error && (
            <div className="text-sm text-destructive bg-destructive/10 rounded-md p-3">
              {error}
            </div>
          )}

          {proofResult && (
            <div className="space-y-4 pt-2">
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
                    <span className="ml-1">{copied ? "Copied" : "Copy"}</span>
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
    </div>
  );
}
