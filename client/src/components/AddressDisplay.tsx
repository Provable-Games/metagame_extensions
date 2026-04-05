import { useState } from "react";
import { padAddress, displayAddress } from "@provable-games/metagame-sdk";

interface AddressDisplayProps {
  address: string;
  className?: string;
}

export function AddressDisplay({ address, className = "" }: AddressDisplayProps) {
  const [copied, setCopied] = useState(false);
  const normalized = padAddress(address);
  const truncated = displayAddress(normalized);

  const handleCopy = async () => {
    await navigator.clipboard.writeText(normalized);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <button
      onClick={handleCopy}
      className={`font-mono text-sm hover:text-primary transition-colors cursor-pointer ${className}`}
      title={`Click to copy: ${normalized}`}
    >
      {copied ? "Copied!" : truncated}
    </button>
  );
}
