import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Loader2 } from "lucide-react";

interface ValidatorConfigCardProps {
  title: string;
  description: string;
  children: React.ReactNode;
  contextId: string;
  onContextIdChange: (id: string) => void;
  isLoading?: boolean;
  hasData?: boolean;
}

export function ValidatorConfigCard({
  title,
  description,
  children,
  contextId,
  onContextIdChange,
  isLoading,
  hasData,
}: ValidatorConfigCardProps) {
  return (
    <div className="rounded-xl border border-border/60 bg-card">
      <div className="p-5 pb-0">
        <h3 className="text-sm font-medium">{title}</h3>
        <p className="text-xs text-muted-foreground mt-0.5">{description}</p>
      </div>
      <div className="p-5 space-y-4">
        <div>
          <Label htmlFor="context-id" className="text-xs">
            Context ID
          </Label>
          <Input
            id="context-id"
            type="number"
            placeholder="Enter context ID"
            value={contextId}
            onChange={(e) => onContextIdChange(e.target.value)}
            className="mt-1.5"
          />
        </div>

        {isLoading && (
          <div className="flex items-center justify-center text-muted-foreground py-6">
            <Loader2 className="h-4 w-4 animate-spin mr-2" />
            <span className="text-xs">Loading config...</span>
          </div>
        )}

        {contextId && hasData && !isLoading && (
          <div className="pt-2 border-t border-border/40">{children}</div>
        )}
      </div>
    </div>
  );
}
