import { Link } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
import { type LucideIcon } from "lucide-react";

interface PageHeaderProps {
  title: string;
  description: string;
  icon: LucideIcon;
  contractAddress?: string;
  backTo?: string;
  action?: React.ReactNode;
}

export function PageHeader({
  title,
  description,
  icon: Icon,
  contractAddress,
  backTo = "/",
  action,
}: PageHeaderProps) {
  return (
    <div className="space-y-3">
      <Link
        to={backTo}
        className="inline-flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
      >
        <ArrowLeft className="h-3 w-3" />
        Back
      </Link>
      <div className="flex items-start justify-between gap-4">
        <div className="flex items-start gap-3 min-w-0">
          <div className="rounded-lg bg-muted p-2.5 mt-0.5 shrink-0">
            <Icon className="h-5 w-5 text-muted-foreground" />
          </div>
          <div className="min-w-0">
            <h1 className="text-xl font-semibold tracking-tight">{title}</h1>
            <p className="text-sm text-muted-foreground mt-0.5">{description}</p>
            {contractAddress && (
              <p className="text-[11px] text-muted-foreground/70 font-mono mt-1.5 break-all">
                {contractAddress}
              </p>
            )}
          </div>
        </div>
        {action && <div className="shrink-0 mt-0.5">{action}</div>}
      </div>
    </div>
  );
}
