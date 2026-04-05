import { useAccount } from "@starknet-react/core";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Link } from "react-router-dom";
import { Plus, Eye, Lock, Camera } from "lucide-react";
import { PageHeader } from "@/components/PageHeader";

export function SnapshotManager() {
  const { isConnected } = useAccount();

  if (!isConnected) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[50vh]">
        <Card className="w-full max-w-md">
          <CardHeader>
            <CardTitle>Welcome to Snapshot Manager</CardTitle>
            <CardDescription>
              Connect your wallet to manage snapshots for entry validation
            </CardDescription>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-muted-foreground">
              Please connect your wallet using one of the options in the header to get started.
            </p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Snapshot management"
        description="Create and manage snapshots for entry validation"
        icon={Camera}
      />

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-6">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Plus className="h-5 w-5" />
              Create Snapshot
            </CardTitle>
            <CardDescription>
              Start a new snapshot and upload player entries
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Link to="/snapshot/create">
              <Button className="w-full">Create New</Button>
            </Link>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Eye className="h-5 w-5" />
              View Snapshots
            </CardTitle>
            <CardDescription>
              Browse and manage your existing snapshots
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Link to="/snapshot/view">
              <Button variant="outline" className="w-full">View All</Button>
            </Link>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Lock className="h-5 w-5" />
              Lock Snapshot
            </CardTitle>
            <CardDescription>
              Finalize a snapshot to make it immutable
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Link to="/snapshot/view">
              <Button variant="secondary" className="w-full">Manage Locks</Button>
            </Link>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}