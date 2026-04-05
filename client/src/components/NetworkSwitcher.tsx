import { useChainConfig } from "@/contexts/NetworkContext";
import { useSwitchNetwork } from "@/hooks/useSwitchNetwork";
import { Button } from "./ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";

export function NetworkSwitcher() {
  const { chainConfig, isMainnet } = useChainConfig();
  const { switchToMainnet, switchToSepolia } = useSwitchNetwork();

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className="gap-2 text-xs font-medium"
        >
          <span
            className={`h-1.5 w-1.5 rounded-full ${
              isMainnet ? "bg-emerald-500" : "bg-amber-500"
            }`}
          />
          <span className="capitalize">{chainConfig.networkName}</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-36">
        <DropdownMenuItem
          onClick={switchToMainnet}
          className={`cursor-pointer text-xs ${isMainnet ? "font-medium" : ""}`}
        >
          <span className="mr-2 h-1.5 w-1.5 rounded-full bg-emerald-500 inline-block" />
          Mainnet
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem
          onClick={switchToSepolia}
          className={`cursor-pointer text-xs ${!isMainnet ? "font-medium" : ""}`}
        >
          <span className="mr-2 h-1.5 w-1.5 rounded-full bg-amber-500 inline-block" />
          Sepolia
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
