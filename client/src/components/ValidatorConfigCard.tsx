import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

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
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div>
          <Label htmlFor="context-id">Context ID</Label>
          <div className="flex gap-2">
            <Input
              id="context-id"
              type="number"
              placeholder="Enter context ID"
              value={contextId}
              onChange={(e) => onContextIdChange(e.target.value)}
            />
          </div>
        </div>

        {isLoading && (
          <div className="text-center text-muted-foreground py-4">Loading config...</div>
        )}

        {contextId && hasData && !isLoading && (
          <div className="space-y-3 pt-2">{children}</div>
        )}
      </CardContent>
    </Card>
  );
}
