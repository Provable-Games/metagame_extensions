import { useState } from "react";
import { Link } from "react-router-dom";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { useChainConfig } from "@/contexts/NetworkContext";
import { MERKLE_VALIDATOR_ABI } from "@/utils/contracts";
import { ValidatorConfigCard } from "@/components/ValidatorConfigCard";
import { useReadContract } from "@starknet-react/core";
import { Button } from "@/components/ui/button";
import { Plus, Search, GitBranch } from "lucide-react";

export function MerkleValidatorPage() {
  const { chainConfig } = useChainConfig();
  const validatorAddress = chainConfig.merkleValidatorAddress;
  const [contextId, setContextId] = useState("");

  const queryArgs = contextId ? [BigInt(contextId)] : undefined;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: treeId, isLoading: loadingTreeId } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: MERKLE_VALIDATOR_ABI,
    functionName: "get_context_tree",
    args: queryArgs,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const treeIdNum = treeId !== undefined ? Number(treeId) : undefined;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: merkleRoot, isLoading: loadingRoot } = useReadContract({
    address: validatorAddress as `0x${string}`,
    abi: MERKLE_VALIDATOR_ABI,
    functionName: "get_tree_root",
    args: treeIdNum ? [BigInt(treeIdNum)] : undefined,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
  } as any);

  const isLoading = loadingTreeId || loadingRoot;
  const hasData = treeIdNum !== undefined;

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Merkle Validator</h1>
        <p className="text-muted-foreground mt-2">
          Entry validation using merkle tree proofs for allowlist-based access
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
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Plus className="h-5 w-5" />
                  Create Merkle Tree
                </CardTitle>
                <CardDescription>
                  Build a merkle tree from a list of addresses and entry counts
                </CardDescription>
              </CardHeader>
              <CardContent>
                <Link to="/merkle/create">
                  <Button className="w-full">Create Tree</Button>
                </Link>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Search className="h-5 w-5" />
                  Proof Lookup
                </CardTitle>
                <CardDescription>
                  Look up an address in a merkle tree to get its proof for
                  contract calls
                </CardDescription>
              </CardHeader>
              <CardContent>
                <Link to="/merkle/proof">
                  <Button variant="outline" className="w-full">
                    Lookup Proof
                  </Button>
                </Link>
              </CardContent>
            </Card>
          </div>

          <ValidatorConfigCard
            title="Context Config"
            description="View the merkle root configured for a context"
            contextId={contextId}
            onContextIdChange={setContextId}
            isLoading={isLoading}
            hasData={!!hasData}
          >
            <div className="grid grid-cols-2 gap-3">
              <div>
                <p className="text-sm text-muted-foreground">Tree ID</p>
                <p className="text-sm font-semibold">
                  {treeIdNum !== undefined && treeIdNum > 0 ? `#${treeIdNum}` : "Not configured"}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Merkle Root</p>
                <p className="text-sm font-mono break-all">
                  {merkleRoot !== undefined ? String(merkleRoot) : "-"}
                </p>
              </div>
            </div>
          </ValidatorConfigCard>

          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <GitBranch className="h-5 w-5" />
                How It Works
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex gap-4">
                <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center text-sm font-semibold">
                  1
                </div>
                <div>
                  <h3 className="font-semibold">Build a Merkle Tree</h3>
                  <p className="text-sm text-muted-foreground">
                    Use the Create Merkle Tree page to build a tree from
                    addresses and entry counts, then download the tree data as
                    JSON
                  </p>
                </div>
              </div>
              <div className="flex gap-4">
                <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center text-sm font-semibold">
                  2
                </div>
                <div>
                  <h3 className="font-semibold">Register Tree On-Chain</h3>
                  <p className="text-sm text-muted-foreground">
                    Register the merkle root on-chain to get a Tree ID, then
                    reference that ID when configuring contexts
                  </p>
                </div>
              </div>
              <div className="flex gap-4">
                <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center text-sm font-semibold">
                  3
                </div>
                <div>
                  <h3 className="font-semibold">Generate Proofs</h3>
                  <p className="text-sm text-muted-foreground">
                    Use the Proof Lookup page to generate merkle proofs for
                    individual addresses to use as qualification data
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>
        </>
      )}
    </div>
  );
}
