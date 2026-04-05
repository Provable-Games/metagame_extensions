import { useState } from "react";
import { normalizeAddress } from "@/utils/address";

interface AddressDisplayProps {
  address: string;
  className?: string;
}

export function AddressDisplay({ address, className = "" }: AddressDisplayProps) {
  const [copied, setCopied] = useState(false);
  const normalized = normalizeAddress(address);
  const truncated = `${normalized.slice(0, 6)}...${normalized.slice(-4)}`;

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
