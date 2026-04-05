import { Outlet, Link } from "react-router-dom";
import { WalletConnect } from "./WalletConnect";
import { NetworkSwitcher } from "./NetworkSwitcher";
import { Shield } from "lucide-react";

export function Layout() {
  return (
    <div className="min-h-dvh bg-background">
      <header className="sticky top-0 z-40 border-b border-border/60 bg-background/80 backdrop-blur-sm">
        <div className="max-w-6xl mx-auto px-6 h-14 flex items-center justify-between">
          <Link
            to="/"
            className="flex items-center gap-2.5 font-semibold text-sm tracking-tight text-foreground hover:text-foreground/80 transition-colors"
          >
            <Shield className="h-5 w-5 text-primary" />
            Metagame Admin
          </Link>
          <div className="flex items-center gap-2">
            <NetworkSwitcher />
            <WalletConnect />
          </div>
        </div>
      </header>
      <main className="max-w-6xl mx-auto px-6 py-8">
        <Outlet />
      </main>
    </div>
  );
}
