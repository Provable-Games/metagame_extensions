import { Link } from "react-router-dom";
import { Card, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useChainConfig } from "@/contexts/NetworkContext";
import { Camera, Coins, Vote, Landmark, Trophy, ShieldCheck, GitBranch } from "lucide-react";

const validators = [
  {
    name: "Snapshot",
    description: "Point-in-time snapshot of player entries. Create, upload, and lock immutable snapshots.",
    path: "/snapshot",
    icon: Camera,
    addressKey: "snapshotValidatorAddress" as const,
  },
  {
    name: "ERC20 Balance",
    description: "Entry based on ERC20 token balance. Entries scale with holdings.",
    path: "/erc20-balance",
    icon: Coins,
    addressKey: "erc20BalanceValidatorAddress" as const,
  },
  {
    name: "Governance",
    description: "Entry based on governance participation and voting power.",
    path: "/governance",
    icon: Vote,
    addressKey: "governanceValidatorAddress" as const,
  },
  {
    name: "Opus Troves",
    description: "Entry based on Opus Protocol debt positions (WAD math).",
    path: "/opus-troves",
    icon: Landmark,
    addressKey: "opusTrovesValidatorAddress" as const,
  },
  {
    name: "Tournament",
    description: "Entry based on participation or placement in prior tournaments.",
    path: "/tournament",
    icon: Trophy,
    addressKey: "tournamentValidatorAddress" as const,
  },
  {
    name: "ZK Passport",
    description: "Entry via zero-knowledge passport proof with sybil prevention.",
    path: "/zk-passport",
    icon: ShieldCheck,
    addressKey: "zkPassportValidatorAddress" as const,
  },
  {
    name: "Merkle",
    description: "Gas-efficient entry validation using merkle proofs. Only the root is stored on-chain.",
    path: "/merkle",
    icon: GitBranch,
    addressKey: "merkleValidatorAddress" as const,
  },
];

export function ValidatorDashboard() {
  const { chainConfig } = useChainConfig();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Entry Validators</h1>
        <p className="text-muted-foreground mt-2">
          Manage and inspect entry validators
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {validators.map((v) => {
          const deployed = !!chainConfig[v.addressKey];
          const Icon = v.icon;
          return (
            <Link key={v.path} to={v.path}>
              <Card className="h-full hover:border-primary/50 transition-colors cursor-pointer">
                <CardHeader>
                  <div className="flex items-center justify-between">
                    <CardTitle className="flex items-center gap-2 text-lg">
                      <Icon className="h-5 w-5" />
                      {v.name}
                    </CardTitle>
                    <span
                      className={`h-2.5 w-2.5 rounded-full ${
                        deployed ? "bg-green-500" : "bg-gray-300"
                      }`}
                      title={deployed ? "Deployed" : "Not deployed on this network"}
                    />
                  </div>
                  <CardDescription>{v.description}</CardDescription>
                </CardHeader>
              </Card>
            </Link>
          );
        })}
      </div>
    </div>
  );
}
