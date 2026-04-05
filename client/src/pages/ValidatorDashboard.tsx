import { Link } from "react-router-dom";
import { useChainConfig } from "@/contexts/NetworkContext";
import {
  Camera,
  Coins,
  Vote,
  Landmark,
  Trophy,
  ShieldCheck,
  GitBranch,
  ArrowRight,
} from "lucide-react";

const validators = [
  {
    name: "Snapshot",
    description: "Point-in-time snapshot of player entries",
    path: "/snapshot",
    icon: Camera,
    addressKey: "snapshotValidatorAddress" as const,
  },
  {
    name: "ERC20 Balance",
    description: "Entries scale with token holdings",
    path: "/erc20-balance",
    icon: Coins,
    addressKey: "erc20BalanceValidatorAddress" as const,
  },
  {
    name: "Governance",
    description: "Participation and voting power",
    path: "/governance",
    icon: Vote,
    addressKey: "governanceValidatorAddress" as const,
  },
  {
    name: "Opus Troves",
    description: "Opus Protocol debt positions",
    path: "/opus-troves",
    icon: Landmark,
    addressKey: "opusTrovesValidatorAddress" as const,
  },
  {
    name: "Tournament",
    description: "Prior tournament placement",
    path: "/tournament",
    icon: Trophy,
    addressKey: "tournamentValidatorAddress" as const,
  },
  {
    name: "ZK Passport",
    description: "Zero-knowledge identity proof",
    path: "/zk-passport",
    icon: ShieldCheck,
    addressKey: "zkPassportValidatorAddress" as const,
  },
  {
    name: "Merkle",
    description: "Allowlist via merkle proofs",
    path: "/merkle",
    icon: GitBranch,
    addressKey: "merkleValidatorAddress" as const,
  },
];

export function ValidatorDashboard() {
  const { chainConfig } = useChainConfig();

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">
          Entry validators
        </h1>
        <p className="text-muted-foreground text-sm mt-1">
          Manage and inspect entry requirement extensions on{" "}
          <span className="capitalize">{chainConfig.networkName}</span>
        </p>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
        {validators.map((v) => {
          const deployed = !!chainConfig[v.addressKey];
          const Icon = v.icon;
          return (
            <Link key={v.path} to={v.path} className="group">
              <div className="relative h-full rounded-xl border border-border/60 bg-card p-5 transition-all duration-200 hover:border-primary/30 hover:bg-accent/50 active:scale-[0.98]">
                <div className="flex items-start justify-between mb-3">
                  <div className="rounded-lg bg-muted p-2.5">
                    <Icon className="h-4 w-4 text-muted-foreground" />
                  </div>
                  <div className="flex items-center gap-2">
                    {deployed && (
                      <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" title="Deployed on this network" />
                    )}
                    <ArrowRight className="h-3.5 w-3.5 text-muted-foreground/0 group-hover:text-muted-foreground transition-all duration-200 -translate-x-1 group-hover:translate-x-0" />
                  </div>
                </div>
                <h3 className="font-medium text-sm">{v.name}</h3>
                <p className="text-xs text-muted-foreground mt-1 leading-relaxed">
                  {v.description}
                </p>
              </div>
            </Link>
          );
        })}
      </div>
    </div>
  );
}
