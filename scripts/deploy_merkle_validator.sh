#!/bin/bash

# Merkle Validator Deployment Script
# Deploys the MerkleValidator contract to Starknet

set -euo pipefail

# Find .env relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
    set -a
    source "$SCRIPT_DIR/../.env"
    set +a
    echo "Loaded environment variables from $SCRIPT_DIR/../.env"
fi

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check deployment environment
STARKNET_NETWORK="${STARKNET_NETWORK:-default}"

# Map network to sncast profile
case "$STARKNET_NETWORK" in
    "mainnet")
        SNCAST_PROFILE="mainnet"
        ;;
    "sepolia")
        SNCAST_PROFILE="sepolia"
        ;;
    *)
        SNCAST_PROFILE="default"
        ;;
esac

# Debug output for environment variables
print_info "Environment variables loaded:"
echo "  STARKNET_NETWORK: $STARKNET_NETWORK"
echo "  SNCAST_PROFILE: $SNCAST_PROFILE"
echo "  STARKNET_RPC: ${STARKNET_RPC:-<from profile>}"

# Build URL flag if STARKNET_RPC is provided
URL_FLAG=""
if [ -n "${STARKNET_RPC:-}" ]; then
    URL_FLAG="--url $STARKNET_RPC"
fi

# ============================
# DISPLAY CONFIGURATION
# ============================

print_info "Deployment Configuration:"
echo "  Network: $STARKNET_NETWORK"
echo "  Profile: $SNCAST_PROFILE"
echo "  RPC: ${STARKNET_RPC:-<from profile>}"
echo ""

# Confirm deployment
if [ "${SKIP_CONFIRMATION:-false}" != "true" ]; then
    read -p "Continue with deployment? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi
fi

# ============================
# BUILD CONTRACTS
# ============================

print_info "Building contracts..."
cd "$SCRIPT_DIR/.."
scarb build

if [ ! -f "target/dev/metagame_extensions_presets_MerkleValidator.contract_class.json" ]; then
    print_error "MerkleValidator contract build failed or contract file not found"
    print_error "Expected: target/dev/metagame_extensions_presets_MerkleValidator.contract_class.json"
    echo "Available contract files:"
    ls -la target/dev/*.contract_class.json 2>/dev/null || echo "No contract files found"
    exit 1
fi

# ============================
# CALCULATE CLASS HASH FIRST
# ============================

print_info "Calculating class hash from artifact..."
CLASS_HASH_OUTPUT=$(sncast --profile $SNCAST_PROFILE utils class-hash \
    --contract-name MerkleValidator \
    --package metagame_extensions_presets 2>&1)
CLASS_HASH=$(echo "$CLASS_HASH_OUTPUT" | grep -oE '0x[0-9a-fA-F]+' | head -1)

if [ -z "$CLASS_HASH" ]; then
    print_error "Could not calculate class hash from artifact"
    echo "Class hash output: $CLASS_HASH_OUTPUT"
    exit 1
fi
print_info "Class hash: $CLASS_HASH"

# ============================
# DECLARE MERKLE VALIDATOR
# ============================

print_info "Declaring MerkleValidator contract..."

DECLARE_OUTPUT=$(sncast --profile $SNCAST_PROFILE --wait declare \
    $URL_FLAG \
    --contract-name MerkleValidator \
    --package metagame_extensions_presets \
    2>&1) || true

# Check declaration result
if echo "$DECLARE_OUTPUT" | grep -qi "class hash:"; then
    print_info "Contract declared successfully"
    print_info "Waiting for declaration to be confirmed..."
    sleep 5
elif echo "$DECLARE_OUTPUT" | grep -qi "already declared"; then
    print_warning "Contract already declared, proceeding with deployment..."
else
    if echo "$DECLARE_OUTPUT" | grep -qi "error"; then
        print_error "Declaration failed"
        echo "Declaration output: $DECLARE_OUTPUT"
        exit 1
    fi
fi

if [ -z "${CLASS_HASH:-}" ]; then
    CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE 'class_hash: 0x[0-9a-fA-F]+' | grep -oE '0x[0-9a-fA-F]+' || echo "$DECLARE_OUTPUT" | grep -oE '0x[0-9a-fA-F]+' | tail -1)
fi

if [ -z "$CLASS_HASH" ]; then
    print_error "Could not extract class hash from declare output"
    echo "$DECLARE_OUTPUT"
    exit 1
fi

print_info "MerkleValidator class hash: $CLASS_HASH"

# ============================
# DEPLOY MERKLE VALIDATOR
# ============================

print_info "Deploying MerkleValidator contract..."

# Retry deployment up to 3 times
MAX_RETRIES=3
RETRY_COUNT=0
CONTRACT_ADDRESS=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ -z "$CONTRACT_ADDRESS" ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))

    if [ $RETRY_COUNT -gt 1 ]; then
        print_warning "Retry attempt $RETRY_COUNT of $MAX_RETRIES..."
        sleep 3
    fi

    DEPLOY_OUTPUT=$(sncast --profile $SNCAST_PROFILE deploy \
        $URL_FLAG \
        --class-hash "$CLASS_HASH" \
        2>&1) || true

    # Extract contract address from output
    if echo "$DEPLOY_OUTPUT" | grep -qi "contract address:"; then
        CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -i "contract address:" | awk '{print $3}')
    elif echo "$DEPLOY_OUTPUT" | grep -q "contract_address:"; then
        CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "contract_address:" | awk '{print $2}')
    elif echo "$DEPLOY_OUTPUT" | grep -qiE "error|failed"; then
        print_warning "Deployment attempt failed: $(echo "$DEPLOY_OUTPUT" | head -1)"
    fi
done

if [ -z "$CONTRACT_ADDRESS" ]; then
    print_error "Failed to deploy contract after $MAX_RETRIES attempts"
    echo "Last deploy output: $DEPLOY_OUTPUT"
    exit 1
fi

print_info "MerkleValidator contract deployed at address: $CONTRACT_ADDRESS"

# ============================
# SAVE DEPLOYMENT INFO
# ============================

DEPLOYMENT_FILE="deployments/merkle_validator_$(date +%Y%m%d_%H%M%S).json"
mkdir -p deployments

cat > "$DEPLOYMENT_FILE" << EOF
{
  "network": "$STARKNET_NETWORK",
  "profile": "$SNCAST_PROFILE",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "merkle_validator": {
    "address": "$CONTRACT_ADDRESS",
    "class_hash": "$CLASS_HASH",
    "description": "Merkle tree-based entry validator using Pedersen proofs for allowlist/weighted entries",
  }
}
EOF

print_info "Deployment info saved to: $DEPLOYMENT_FILE"

# ============================
# DEPLOYMENT SUMMARY
# ============================

echo
print_info "=== DEPLOYMENT SUCCESSFUL ==="
echo
echo "Merkle Validator Contract:"
echo "  Address: $CONTRACT_ADDRESS"
echo "  Class Hash: $CLASS_HASH"
echo ""

echo "Next steps:"
echo "1. Create a merkle tree by calling create_tree(root) with your computed root"
echo "2. Use the returned tree_id when configuring tournaments via add_config"
echo "3. Players submit merkle proofs as qualification data to enter tournaments"
echo ""

echo "To interact with the contract:"
echo "  export MERKLE_VALIDATOR=$CONTRACT_ADDRESS"
echo ""

echo "Example: Create a merkle tree:"
echo "  sncast --profile $SNCAST_PROFILE --url \$STARKNET_RPC invoke \\"
echo "    --contract-address \$MERKLE_VALIDATOR \\"
echo "    --function create_tree \\"
echo "    --calldata <merkle_root>"
echo ""

echo "Example: Verify a proof:"
echo "  sncast --profile $SNCAST_PROFILE --url \$STARKNET_RPC call \\"
echo "    --contract-address \$MERKLE_VALIDATOR \\"
echo "    --function verify_proof \\"
echo "    --calldata <tree_id> <player_address> <count> <proof_len> <proof...>"
echo ""
