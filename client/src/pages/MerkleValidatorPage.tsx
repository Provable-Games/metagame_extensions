import { useState, useEffect, useMemo } from "react";
import { Link } from "react-router-dom";
import { useChainConfig } from "@/contexts/NetworkContext";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { PageHeader } from "@/components/PageHeader";
import {
  Plus,
  GitBranch,
  ChevronLeft,
  ChevronRight,
  Loader2,
  Search,
  ArrowRight,
} from "lucide-react";
import {
  fetchMerkleTrees,
  type MerkleTree,
  type MerkleTreesResponse,
} from "@provable-games/metagame-sdk";

export function MerkleValidatorPage() {
  const { chainConfig } = useChainConfig();
  const validatorAddress = chainConfig.merkleValidatorAddress;

  const [treesResponse, setTreesResponse] =
    useState<MerkleTreesResponse | null>(null);
  const [treesLoading, setTreesLoading] = useState(false);
  const [page, setPage] = useState(1);
  const limit = 10;
  const [search, setSearch] = useState("");

  useEffect(() => {
    if (!validatorAddress) return;
    setTreesLoading(true);
    fetchMerkleTrees({ page, limit, chainId: chainConfig.chainId })
      .then(setTreesResponse)
      .finally(() => setTreesLoading(false));
  }, [validatorAddress, page, chainConfig.chainId]);

  const trees = treesResponse?.data ?? [];
  const totalPages = treesResponse?.totalPages ?? 0;

  const filteredTrees = useMemo(() => {
    if (!search.trim()) return trees;
    const q = search.trim().toLowerCase();
    return trees.filter(
      (t) =>
        String(t.id) === q ||
        String(t.id).includes(q) ||
        t.name.toLowerCase().includes(q),
    );
  }, [trees, search]);

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <PageHeader
        title="Merkle validator"
        description="Allowlist-based entry validation using merkle proofs"
        icon={GitBranch}
        contractAddress={validatorAddress}
        action={
          validatorAddress ? (
            <Link to="/merkle/create">
              <Button size="sm">
                <Plus className="h-3.5 w-3.5 mr-1.5" />
                Create tree
              </Button>
            </Link>
          ) : undefined
        }
      />

      {!validatorAddress ? (
        <div className="text-sm text-muted-foreground bg-muted/50 rounded-lg p-4">
          This validator is not deployed on the current network.
        </div>
      ) : (
        <>
          {treesLoading ? (
            <div className="flex items-center justify-center py-16 text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin mr-2" />
              <span className="text-sm">Loading trees...</span>
            </div>
          ) : trees.length === 0 ? (
            <div className="text-center py-16 space-y-3">
              <div className="rounded-lg bg-muted/50 p-3 inline-block">
                <GitBranch className="h-6 w-6 text-muted-foreground" />
              </div>
              <div>
                <p className="text-sm text-muted-foreground">
                  No trees created yet
                </p>
                <Link
                  to="/merkle/create"
                  className="text-sm text-primary hover:underline"
                >
                  Create your first tree
                </Link>
              </div>
            </div>
          ) : (
            <div className="space-y-3">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-muted-foreground" />
                <Input
                  placeholder="Search by ID or name..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  className="pl-9 h-9 text-sm"
                />
              </div>

              {filteredTrees.length === 0 ? (
                <p className="text-sm text-muted-foreground text-center py-8">
                  No trees match "{search}"
                </p>
              ) : (
                <div className="space-y-2">
                  {filteredTrees.map((tree: MerkleTree) => (
                    <Link
                      key={tree.id}
                      to={`/merkle/tree/${tree.id}`}
                      className="group block"
                    >
                      <div className="rounded-xl border border-border/60 bg-card p-4 flex items-start justify-between gap-4 transition-all duration-200 hover:border-primary/30 hover:bg-accent/30 active:scale-[0.99]">
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center gap-2">
                            <span className="text-sm font-medium">
                              #{tree.id}
                            </span>
                            <span className="text-sm text-muted-foreground truncate">
                              {tree.name}
                            </span>
                          </div>
                          {tree.description && (
                            <p className="text-xs text-muted-foreground/70 mt-0.5 truncate">
                              {tree.description}
                            </p>
                          )}
                        </div>
                        <div className="flex items-center gap-3 shrink-0">
                          <div className="text-right">
                            <p className="text-sm tabular-nums">
                              {tree.entryCount}{" "}
                              {tree.entryCount === 1 ? "address" : "addresses"}
                            </p>
                            <p className="text-[11px] text-muted-foreground/60">
                              {new Date(tree.createdAt).toLocaleDateString()}
                            </p>
                          </div>
                          <ArrowRight className="h-3.5 w-3.5 text-muted-foreground/0 group-hover:text-muted-foreground transition-all duration-200 -translate-x-1 group-hover:translate-x-0" />
                        </div>
                      </div>
                    </Link>
                  ))}
                </div>
              )}

              {totalPages > 1 && !search && (
                <div className="flex items-center justify-between pt-1">
                  <Button
                    size="sm"
                    variant="ghost"
                    disabled={page <= 1}
                    onClick={() => setPage((p) => p - 1)}
                  >
                    <ChevronLeft className="h-4 w-4" />
                  </Button>
                  <span className="text-xs text-muted-foreground tabular-nums">
                    {page} / {totalPages}
                  </span>
                  <Button
                    size="sm"
                    variant="ghost"
                    disabled={page >= totalPages}
                    onClick={() => setPage((p) => p + 1)}
                  >
                    <ChevronRight className="h-4 w-4" />
                  </Button>
                </div>
              )}
            </div>
          )}
        </>
      )}
    </div>
  );
}
