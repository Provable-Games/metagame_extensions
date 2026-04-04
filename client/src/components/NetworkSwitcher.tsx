import { useAccount } from "@starknet-react/core";
import { Globe } from "lucide-react";
import { useChainConfig } from "@/contexts/NetworkContext";
import { useSwitchNetwork } from "@/hooks/useSwitchNetwork";
import { Button } from "./ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";

export function NetworkSwitcher() {
  const { status } = useAccount();
  const { chainConfig, isMainnet } = useChainConfig();
  const { switchToMainnet, switchToSepolia } = useSwitchNetwork();

  // Show switcher always so shared links can be changed before connecting

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="outline"
          size="sm"
          className={`flex items-center gap-2 ${
            isMainnet
              ? "border-green-500/50 text-green-600 dark:text-green-400"
              : "border-yellow-500/50 text-yellow-600 dark:text-yellow-400"
          }`}
        >
          <Globe className="h-4 w-4" />
          <span className="capitalize">{chainConfig.networkName}</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-40">
        <DropdownMenuLabel>Network</DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuItem
          onClick={switchToMainnet}
          className={`cursor-pointer ${isMainnet ? "font-semibold" : ""}`}
        >
          <span className="mr-2 h-2 w-2 rounded-full bg-green-500 inline-block" />
          Mainnet
        </DropdownMenuItem>
        <DropdownMenuItem
          onClick={switchToSepolia}
          className={`cursor-pointer ${!isMainnet ? "font-semibold" : ""}`}
        >
          <span className="mr-2 h-2 w-2 rounded-full bg-yellow-500 inline-block" />
          Sepolia
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
