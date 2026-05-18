#!/usr/bin/env bash

ANVIL_RPC_URL="http://127.0.0.1:8545"
# Anvil's first pre-funded account — public knowledge, safe to hardcode in tests
ANVIL_PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

wait_for_anvil() {
  local i=0
  until cast chain-id --rpc-url "$ANVIL_RPC_URL" &>/dev/null; do
    sleep 0.1
    (( i++ ))
    [[ $i -lt 50 ]] || { echo "Anvil failed to start after 5 seconds" >&2; return 1; }
  done
}
