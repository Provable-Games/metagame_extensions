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
import { Upload, Plus, Trash2, GitBranch, Copy, Check } from "lucide-react";
import { buildMerkleTree, type MerkleEntry } from "@/utils/merkleTree";
import { useChainConfig } from "@/contexts/NetworkContext";
import { MERKLE_API_URL } from "@/networks";

export function CreateMerkleTree() {
  const { account } = useAccount();
  const { provider } = useProvider();
  const { chainConfig } = useChainConfig();
  const validatorAddress = chainConfig.merkleValidatorAddress;
  const [treeName, setTreeName] = useState("");
  const [treeDescription, setTreeDescription] = useState("");
  const [entries, setEntries] = useState<MerkleEntry[]>([]);
  const [newAddress, setNewAddress] = useState("");
  const [newCount, setNewCount] = useState("");
  const [csvContent, setCsvContent] = useState("");
  const [error, setError] = useState("");
  const [copied, setCopied] = useState(false);
  const [isCreating, setIsCreating] = useState(false);
  const [status, setStatus] = useState("");

  // Result state
  const [result, setResult] = useState<{
    treeId: string;
    root: string;
    entryCount: number;
  } | null>(null);

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
      setResult(null);
    }
  };

  const handleRemoveEntry = (index: number) => {
    setEntries(entries.filter((_, i) => i !== index));
    setResult(null);
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
    setResult(null);
  };

  const handleCreate = async () => {
    if (entries.length === 0 || !account || !validatorAddress) return;
    setIsCreating(true);
    setError("");
    setResult(null);

    try {
      // Step 1: Build tree client-side
      setStatus("Building merkle tree...");
      const tree = buildMerkleTree(entries);

      // Step 2: Register on-chain
      setStatus("Registering on-chain...");
      const txResult = await account.execute({
        contractAddress: validatorAddress,
        entrypoint: "create_tree",
        calldata: [tree.root],
      });

      setStatus("Waiting for transaction confirmation...");
      const receipt = await provider.waitForTransaction(
        txResult.transaction_hash,
      );

      // Parse tree ID from event
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const events = (receipt as any).events || [];
      // Compare addresses as BigInt to handle padding differences
      const validatorBigInt = BigInt(validatorAddress);
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const treeEvent = events.find((e: any) => {
        try {
          return BigInt(e.from_address) === validatorBigInt;
        } catch {
          return false;
        }
      });

      if (!treeEvent?.keys?.[1]) {
        console.error("Events received:", JSON.stringify(events, null, 2));
        setError("Transaction succeeded but could not parse tree ID from events");
        return;
      }

      const treeId = Number(BigInt(treeEvent.keys[1]));

      // Step 3: Store in API with the on-chain tree ID
      setStatus("Storing proofs in API...");
      const res = await fetch(`${MERKLE_API_URL}/trees`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id: treeId, name: treeName, description: treeDescription, entries }),
      });

      if (!res.ok) {
        const errText = await res.text();
        setError(
          `On-chain tree #${treeId} created, but failed to store proofs in API: ${errText}`,
        );
        setResult({ treeId: String(treeId), root: tree.root, entryCount: entries.length });
        return;
      }

      setResult({ treeId: String(treeId), root: tree.root, entryCount: entries.length });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to create merkle tree");
    } finally {
      setIsCreating(false);
      setStatus("");
    }
  };

  const handleCopyRoot = async () => {
    if (!result) return;
    await navigator.clipboard.writeText(result.root);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Create Merkle Tree</h1>
        <p className="text-muted-foreground mt-2">
          Add entries, register the merkle root on-chain, and store proofs for
          lookup
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
                  placeholder={"address,count\n0x123...,5\n0x456...,3"}
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

      {entries.length > 0 && !result && (
        <Card>
          <CardHeader>
            <CardTitle>Create Tree</CardTitle>
            <CardDescription>
              Build the merkle tree, register it on-chain, and store proofs
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div>
              <Label htmlFor="treeName">Name</Label>
              <Input
                id="treeName"
                placeholder="e.g., OG Players"
                value={treeName}
                onChange={(e) => setTreeName(e.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="treeDescription">Description</Label>
              <Input
                id="treeDescription"
                placeholder="e.g., Early adopters from Season 1"
                value={treeDescription}
                onChange={(e) => setTreeDescription(e.target.value)}
              />
            </div>
            {!account && (
              <div className="text-sm text-muted-foreground bg-muted rounded-md p-3">
                Connect your wallet to create a merkle tree.
              </div>
            )}
            {!validatorAddress && (
              <div className="text-sm text-muted-foreground bg-muted rounded-md p-3">
                Merkle validator is not deployed on this network.
              </div>
            )}
            <Button
              onClick={handleCreate}
              disabled={isCreating || !account || !validatorAddress}
              className="w-full"
            >
              <GitBranch className="h-4 w-4 mr-2" />
              {isCreating ? status || "Creating..." : "Create Merkle Tree"}
            </Button>
          </CardContent>
        </Card>
      )}

      {result && (
        <Card>
          <CardHeader>
            <CardTitle>Tree Created</CardTitle>
            <CardDescription>
              Merkle tree registered on-chain and proofs stored in the API
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <p className="text-sm text-muted-foreground">Tree ID</p>
                <p className="text-lg font-semibold">#{result.treeId}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Entries</p>
                <p className="text-lg font-semibold">{result.entryCount}</p>
              </div>
              {treeName && (
                <div className="col-span-2">
                  <p className="text-sm text-muted-foreground">Name</p>
                  <p className="text-sm font-medium">{treeName}</p>
                </div>
              )}
              <div className="col-span-2">
                <p className="text-sm text-muted-foreground">Merkle Root</p>
                <div className="flex items-center gap-2">
                  <p className="text-sm font-mono break-all flex-1">
                    {result.root}
                  </p>
                  <Button size="icon" variant="ghost" onClick={handleCopyRoot}>
                    {copied ? (
                      <Check className="h-4 w-4 text-green-500" />
                    ) : (
                      <Copy className="h-4 w-4" />
                    )}
                  </Button>
                </div>
              </div>
            </div>

            <div className="bg-green-50 dark:bg-green-950 border border-green-200 dark:border-green-800 rounded-md p-3 space-y-1">
              <p className="text-sm text-green-800 dark:text-green-200">
                Use <span className="font-semibold">Tree #{result.treeId}</span>{" "}
                when configuring contexts with the Merkle Validator.
              </p>
              <p className="text-xs text-green-700 dark:text-green-300">
                Proofs: {MERKLE_API_URL}/trees/{result.treeId}/proof/ADDRESS
              </p>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
