import { Outlet, Link, useLocation } from "react-router-dom";
import { WalletConnect } from "./WalletConnect";
import { NetworkSwitcher } from "./NetworkSwitcher";
import { Shield } from "lucide-react";

const navLinks = [
  { label: "Dashboard", path: "/" },
  { label: "Snapshot", path: "/snapshot" },
  { label: "ERC20", path: "/erc20-balance" },
  { label: "Governance", path: "/governance" },
  { label: "Opus", path: "/opus-troves" },
  { label: "Tournament", path: "/tournament" },
  { label: "ZK Passport", path: "/zk-passport" },
  { label: "Merkle", path: "/merkle" },
];

export function Layout() {
  const location = useLocation();

  const isActive = (path: string) => {
    if (path === "/") return location.pathname === "/";
    return location.pathname.startsWith(path);
  };

  return (
    <div className="min-h-screen bg-background">
      <header className="border-b">
        <div className="container mx-auto px-4 py-4">
          <nav className="flex items-center justify-between">
            <div className="flex items-center gap-6">
              <Link to="/" className="flex items-center gap-2 font-semibold text-lg">
                <Shield className="h-6 w-6" />
                Metagame Admin
              </Link>
              <div className="flex items-center gap-4">
                {navLinks.map((link) => (
                  <Link
                    key={link.path}
                    to={link.path}
                    className={`text-sm transition-colors ${
                      isActive(link.path)
                        ? "text-foreground font-medium"
                        : "text-muted-foreground hover:text-foreground"
                    }`}
                  >
                    {link.label}
                  </Link>
                ))}
              </div>
            </div>
            <div className="flex items-center gap-2">
              <NetworkSwitcher />
              <WalletConnect />
            </div>
          </nav>
        </div>
      </header>
      <main className="container mx-auto px-4 py-8">
        <Outlet />
      </main>
    </div>
  );
}
