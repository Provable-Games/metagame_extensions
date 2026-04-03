import { useState } from "react";
import { useAccount, useProvider } from "@starknet-react/core";
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
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  Upload,
  Plus,
  Trash2,
  GitBranch,
  Copy,
  Check,
} from "lucide-react";
import {
  buildMerkleTree,
  type MerkleTreeData,
  type MerkleEntry,
} from "@/utils/merkleTree";
import { useChainConfig } from "@/contexts/NetworkContext";
import { MERKLE_API_URL } from "@/networks";

export function CreateMerkleTree() {
  const { account } = useAccount();
  const { provider } = useProvider();
  const { chainConfig } = useChainConfig();
  const validatorAddress = chainConfig.merkleValidatorAddress;
  const [entries, setEntries] = useState<MerkleEntry[]>([]);
  const [treeData, setTreeData] = useState<MerkleTreeData | null>(null);
  const [newAddress, setNewAddress] = useState("");
  const [newCount, setNewCount] = useState("");
  const [csvContent, setCsvContent] = useState("");
  const [error, setError] = useState("");
  const [copied, setCopied] = useState(false);
  const [isRegistering, setIsRegistering] = useState(false);
  const [treeId, setTreeId] = useState<string | null>(null);

  const handleAddEntry = () => {
    if (newAddress && newCount) {
      const count = parseInt(newCount);
      if (isNaN(count) || count <= 0) {
        setError("Count must be a positive number");
        return;
      }
      setEntries([...entries, { address: newAddress, count }]);
      setNewAddress("");
      setNewCount("");
      setError("");
      setTreeData(null);
    }
  };

  const handleRemoveEntry = (index: number) => {
    setEntries(entries.filter((_, i) => i !== index));
    setTreeData(null);
  };

  const handleParseCsv = () => {
    const lines = csvContent.trim().split("\n");
    const parsedEntries: MerkleEntry[] = [];

    for (const line of lines) {
      const [address, count] = line.split(",").map((s) => s.trim());
      if (address && count) {
        const parsedCount = parseInt(count);
        if (!isNaN(parsedCount) && parsedCount > 0) {
          parsedEntries.push({ address, count: parsedCount });
        }
      }
    }

    if (parsedEntries.length === 0) {
      setError("No valid entries found in CSV");
      return;
    }

    setEntries(parsedEntries);
    setCsvContent("");
    setError("");
    setTreeData(null);
  };

  const [apiTreeId, setApiTreeId] = useState<number | null>(null);

  const handleBuild = async () => {
    if (entries.length === 0) return;
    try {
      // Build tree client-side
      const tree = buildMerkleTree(entries);
      setTreeData(tree);
      setError("");

      // Store entries + proofs in the API
      const res = await fetch(`${MERKLE_API_URL}/trees`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ entries }),
      });
      if (res.ok) {
        const data = await res.json();
        setApiTreeId(data.id);
      } else {
        const errText = await res.text();
        setError(`Tree built locally but failed to store in API: ${errText}`);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to build merkle tree");
    }
  };

  const handleCopyRoot = async () => {
    if (!treeData) return;
    await navigator.clipboard.writeText(treeData.root);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleRegisterOnChain = async () => {
    if (!account || !treeData || !validatorAddress) return;
    setIsRegistering(true);
    try {
      const result = await account.execute({
        contractAddress: validatorAddress,
        entrypoint: "create_tree",
        calldata: [treeData.root],
      });
      const receipt = await provider.waitForTransaction(result.transaction_hash);
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const events = (receipt as any).events || [];
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const treeEvent = events.find((e: any) =>
        e.from_address?.toLowerCase() === validatorAddress.toLowerCase()
      );
      if (treeEvent?.keys?.[1]) {
        setTreeId(BigInt(treeEvent.keys[1]).toString());
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to register tree on-chain");
    } finally {
      setIsRegistering(false);
    }
  };

  // Compute tree depth from leaf count
  const treeDepth = treeData
    ? Math.ceil(Math.log2(treeData.entries.length))
    : 0;

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Create Merkle Tree</h1>
        <p className="text-muted-foreground mt-2">
          Build a merkle tree from addresses and entry counts. This is done
          entirely client-side — no wallet connection required.
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Add Entries</CardTitle>
          <CardDescription>
            Add player addresses and their entry counts via manual input or CSV
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Tabs defaultValue="manual">
            <TabsList className="grid w-full grid-cols-2">
              <TabsTrigger value="manual">Manual Entry</TabsTrigger>
              <TabsTrigger value="csv">CSV Upload</TabsTrigger>
            </TabsList>

            <TabsContent value="manual" className="space-y-4">
              <div className="flex gap-2">
                <div className="flex-1">
                  <Label htmlFor="address">Address</Label>
                  <Input
                    id="address"
                    placeholder="0x..."
                    value={newAddress}
                    onChange={(e) => setNewAddress(e.target.value)}
                  />
                </div>
                <div className="w-32">
                  <Label htmlFor="count">Count</Label>
                  <Input
                    id="count"
                    type="number"
                    placeholder="1"
                    value={newCount}
                    onChange={(e) => setNewCount(e.target.value)}
                  />
                </div>
                <div className="flex items-end">
                  <Button onClick={handleAddEntry} size="icon">
                    <Plus className="h-4 w-4" />
                  </Button>
                </div>
              </div>
            </TabsContent>

            <TabsContent value="csv" className="space-y-4">
              <div>
                <Label htmlFor="csv">CSV Data</Label>
                <textarea
                  id="csv"
                  className="w-full h-32 px-3 py-2 text-sm rounded-md border border-input bg-background"
                  placeholder={
                    "address,count\n0x123...,5\n0x456...,3"
                  }
                  value={csvContent}
                  onChange={(e) => setCsvContent(e.target.value)}
                />
              </div>
              <Button onClick={handleParseCsv} className="w-full">
                <Upload className="h-4 w-4 mr-2" />
                Parse CSV
              </Button>
            </TabsContent>
          </Tabs>

          {error && (
            <div className="mt-4 text-sm text-destructive bg-destructive/10 rounded-md p-3">
              {error}
            </div>
          )}

          {entries.length > 0 && (
            <div className="mt-6 space-y-2">
              <h3 className="font-semibold text-sm">
                Entries ({entries.length})
              </h3>
              <div className="max-h-64 overflow-y-auto space-y-2">
                {entries.map((entry, index) => (
                  <div
                    key={index}
                    className="flex items-center gap-2 p-2 border rounded"
                  >
                    <span className="flex-1 text-sm font-mono truncate">
                      {entry.address}
                    </span>
                    <span className="text-sm font-semibold">{entry.count}</span>
                    <Button
                      size="icon"
                      variant="ghost"
                      onClick={() => handleRemoveEntry(index)}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                ))}
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {entries.length > 0 && !treeData && (
        <Card>
          <CardHeader>
            <CardTitle>Build Tree</CardTitle>
            <CardDescription>
              Compute the merkle tree from the entries above
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Button onClick={handleBuild} className="w-full">
              <GitBranch className="h-4 w-4 mr-2" />
              Build Merkle Tree
            </Button>
          </CardContent>
        </Card>
      )}

      {treeData && (
        <Card>
          <CardHeader>
            <CardTitle>Merkle Tree Result</CardTitle>
            <CardDescription>
              Tree built successfully. Use this root when configuring a context
              with the Merkle Validator.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-2 gap-3">
              <div className="col-span-2">
                <p className="text-sm text-muted-foreground">Merkle Root</p>
                <div className="flex items-center gap-2">
                  <p className="text-sm font-mono break-all flex-1">
                    {treeData.root}
                  </p>
                  <Button
                    size="icon"
                    variant="ghost"
                    onClick={handleCopyRoot}
                  >
                    {copied ? (
                      <Check className="h-4 w-4 text-green-500" />
                    ) : (
                      <Copy className="h-4 w-4" />
                    )}
                  </Button>
                </div>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Entries</p>
                <p className="text-sm font-semibold">
                  {treeData.entries.length}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Tree Depth</p>
                <p className="text-sm font-semibold">{treeDepth}</p>
              </div>
            </div>

            {validatorAddress && account && (
              <Button
                onClick={handleRegisterOnChain}
                disabled={isRegistering || !!treeId}
                className="w-full"
              >
                {isRegistering
                  ? "Registering..."
                  : treeId
                    ? `Tree #${treeId}`
                    : "Register On-Chain"}
              </Button>
            )}

            {treeId && (
              <div className="bg-green-50 dark:bg-green-950 border border-green-200 dark:border-green-800 rounded-md p-3">
                <p className="text-sm text-green-800 dark:text-green-200">
                  Registered as <span className="font-semibold">Tree #{treeId}</span>. Use this ID when configuring contexts with the Merkle Validator.
                </p>
              </div>
            )}

            {apiTreeId && (
              <div className="text-sm text-muted-foreground bg-muted rounded-md p-3">
                Proofs stored in API (tree #{apiTreeId}). Proofs can be fetched at:{" "}
                <code className="text-xs">{MERKLE_API_URL}/trees/{apiTreeId}/proof/ADDRESS</code>
              </div>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  );
}
