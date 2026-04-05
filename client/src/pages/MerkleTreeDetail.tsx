import { useState, useEffect } from "react";
import { useParams } from "react-router-dom";
import { useChainConfig } from "@/contexts/NetworkContext";
import { Button } from "@/components/ui/button";
import { PageHeader } from "@/components/PageHeader";
import {
  padAddress,
  displayAddress,
  fetchMerkleTreeEntries,
  type MerkleTreeEntriesResponse,
} from "@provable-games/metagame-sdk";
import { createMerkleClient, type MerkleTree } from "@provable-games/metagame-sdk/merkle";
import {
  GitBranch,
  ChevronLeft,
  ChevronRight,
  Loader2,
  Download,
} from "lucide-react";

export function MerkleTreeDetail() {
  const { id } = useParams();
  const { chainConfig } = useChainConfig();
  const treeId = id ? Number(id) : null;

  const [tree, setTree] = useState<MerkleTree | null>(null);
  const [treeLoading, setTreeLoading] = useState(true);
  const [entriesResponse, setEntriesResponse] =
    useState<MerkleTreeEntriesResponse | null>(null);
  const [entriesLoading, setEntriesLoading] = useState(false);
  const [entriesPage, setEntriesPage] = useState(1);
  const [exporting, setExporting] = useState(false);
  const entriesLimit = 50;

  // Fetch tree metadata by ID
  useEffect(() => {
    if (treeId === null) return;
    setTreeLoading(true);
    const client = createMerkleClient({ chainId: chainConfig.chainId });
    client
      .getTree(treeId)
      .then((found) => setTree(found))
      .finally(() => setTreeLoading(false));
  }, [treeId, chainConfig.chainId]);

  // Fetch entries
  useEffect(() => {
    if (treeId === null) return;
    setEntriesLoading(true);
    fetchMerkleTreeEntries(treeId, {
      page: entriesPage,
      limit: entriesLimit,
      chainId: chainConfig.chainId,
    })
      .then(setEntriesResponse)
      .finally(() => setEntriesLoading(false));
  }, [treeId, entriesPage, chainConfig.chainId]);

  const handleExportCsv = async () => {
    if (treeId === null) return;
    setExporting(true);
    try {
      // Fetch all entries (up to 10k)
      const allEntries: Array<{ address: string; count: number }> = [];
      let page = 1;
      const batchSize = 1000;
      let hasMore = true;

      while (hasMore) {
        const res = await fetchMerkleTreeEntries(treeId, {
          page,
          limit: batchSize,
          chainId: chainConfig.chainId,
        });
        allEntries.push(...res.data);
        hasMore = page < res.totalPages;
        page++;
      }

      const csv =
        "address,count\n" +
        allEntries
          .map((e) => `${padAddress(e.address)},${e.count}`)
          .join("\n");

      const blob = new Blob([csv], { type: "text/csv" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `merkle-tree-${treeId}.csv`;
      a.click();
      URL.revokeObjectURL(url);
    } finally {
      setExporting(false);
    }
  };

  const entries = entriesResponse?.data ?? [];
  const entriesTotalPages = entriesResponse?.totalPages ?? 0;
  const entriesTotal = entriesResponse?.total ?? 0;

  if (treeLoading) {
    return (
      <div className="max-w-3xl mx-auto flex items-center justify-center py-24 text-muted-foreground">
        <Loader2 className="h-4 w-4 animate-spin mr-2" />
        <span className="text-sm">Loading tree...</span>
      </div>
    );
  }

  if (!tree) {
    return (
      <div className="max-w-3xl mx-auto space-y-6">
        <PageHeader
          title="Tree not found"
          description={`No tree with ID ${id} was found`}
          icon={GitBranch}
          backTo="/merkle"
        />
      </div>
    );
  }

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <PageHeader
        title={tree.name || `Tree #${tree.id}`}
        description={tree.description || "Merkle tree"}
        icon={GitBranch}
        backTo="/merkle"
        action={
          <Button
            size="sm"
            variant="outline"
            onClick={handleExportCsv}
            disabled={exporting || entriesTotal === 0}
          >
            <Download className="h-3.5 w-3.5 mr-1.5" />
            {exporting ? "Exporting..." : "Export CSV"}
          </Button>
        }
      />

      {/* Tree metadata */}
      <div className="grid grid-cols-3 gap-4">
        <div className="rounded-xl border border-border/60 bg-card p-4">
          <p className="text-[11px] text-muted-foreground mb-1">Tree ID</p>
          <p className="text-lg font-medium tabular-nums">#{tree.id}</p>
        </div>
        <div className="rounded-xl border border-border/60 bg-card p-4">
          <p className="text-[11px] text-muted-foreground mb-1">Addresses</p>
          <p className="text-lg font-medium tabular-nums">{tree.entryCount}</p>
        </div>
        <div className="rounded-xl border border-border/60 bg-card p-4">
          <p className="text-[11px] text-muted-foreground mb-1">Created</p>
          <p className="text-sm font-medium">
            {new Date(tree.createdAt).toLocaleDateString()}
          </p>
        </div>
      </div>

      <div className="rounded-xl border border-border/60 bg-card p-4">
        <p className="text-[11px] text-muted-foreground mb-1">Root</p>
        <p className="text-xs font-mono text-muted-foreground break-all leading-relaxed">
          {tree.root}
        </p>
      </div>

      {/* Entries */}
      <div>
        <div className="flex items-center justify-between mb-3">
          <p className="text-sm font-medium">
            Addresses
            {entriesTotal > 0 && (
              <span className="text-muted-foreground font-normal ml-1.5">
                ({entriesTotal})
              </span>
            )}
          </p>
        </div>

        {entriesLoading && entries.length === 0 ? (
          <div className="flex items-center justify-center py-12 text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin mr-2" />
            <span className="text-sm">Loading entries...</span>
          </div>
        ) : entries.length === 0 ? (
          <p className="text-sm text-muted-foreground text-center py-12">
            No entries found
          </p>
        ) : (
          <>
            <div className="rounded-xl border border-border/60 overflow-hidden">
              <table className="w-full text-xs">
                <thead>
                  <tr className="bg-muted/30">
                    <th className="text-left font-medium text-muted-foreground px-4 py-2.5">
                      Address
                    </th>
                    <th className="text-right font-medium text-muted-foreground px-4 py-2.5 w-24">
                      Entries
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {entries.map((entry, i) => (
                    <tr key={i} className="border-t border-border/30">
                      <td className="px-4 py-2 font-mono text-muted-foreground">
                        <span
                          className="hidden sm:inline"
                          title={padAddress(entry.address)}
                        >
                          {padAddress(entry.address)}
                        </span>
                        <span className="sm:hidden">
                          {displayAddress(padAddress(entry.address))}
                        </span>
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums">
                        {entry.count}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {entriesTotalPages > 1 && (
              <div className="flex items-center justify-between pt-3">
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={entriesPage <= 1}
                  onClick={() => setEntriesPage((p) => p - 1)}
                >
                  <ChevronLeft className="h-4 w-4" />
                </Button>
                <span className="text-xs text-muted-foreground tabular-nums">
                  {entriesPage} / {entriesTotalPages}
                </span>
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={entriesPage >= entriesTotalPages}
                  onClick={() => setEntriesPage((p) => p + 1)}
                >
                  <ChevronRight className="h-4 w-4" />
                </Button>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
