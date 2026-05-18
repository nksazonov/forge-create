#!/usr/bin/env bats

load helpers/anvil

FORGE_CREATE="$BATS_TEST_DIRNAME/../forge-create.sh"
CONTRACT="fixtures/Counter.sol:Counter"
CONTRACT_DIR_NAME="Counter.sol_Counter"

setup_file() {
  anvil --port 8545 &>/tmp/anvil-test.log &
  export ANVIL_PID=$!
  wait_for_anvil
}

teardown_file() {
  kill "$ANVIL_PID" 2>/dev/null || true
}

# Snapshot taken before each test; reverted after in teardown.
# setup() and teardown() run in the same subshell per test, so SNAPSHOT_ID
# is shared between them without needing export or file persistence.
setup() {
  SNAPSHOT_ID=$(cast rpc anvil_snapshot --rpc-url "$ANVIL_RPC_URL" | tr -d '"')
}

teardown() {
  cast rpc anvil_revert --rpc-url "$ANVIL_RPC_URL" "$SNAPSHOT_ID" > /dev/null 2>&1 || true
}

# Run forge-create from the test/ directory so foundry.toml is on the search path.
forge_create() {
  (cd "$BATS_TEST_DIRNAME" && "$FORGE_CREATE" "$@")
}

@test "happy path: file created with correct JSON fields" {
  run forge_create "$CONTRACT" \
    --rpc-url "$ANVIL_RPC_URL" \
    --private-key "$ANVIL_PRIVATE_KEY" \
    --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]

  local saved
  saved=$(find "$BATS_TEST_TMPDIR/31337/$CONTRACT_DIR_NAME" -name "*.json" 2>/dev/null | head -1)
  [ -n "$saved" ]

  jq -e '.deployer | test("^0x[0-9a-fA-F]{40}$")' "$saved" > /dev/null
  jq -e '.deployedTo | test("^0x[0-9a-fA-F]{40}$")' "$saved" > /dev/null
  jq -e '.chainId == 31337' "$saved" > /dev/null
  jq -e '.commit | test("^[0-9a-f]{40}$")' "$saved" > /dev/null
}

@test "--file-prefix prepends to filename" {
  run forge_create "$CONTRACT" \
    --rpc-url "$ANVIL_RPC_URL" \
    --private-key "$ANVIL_PRIVATE_KEY" \
    --save-out "$BATS_TEST_TMPDIR" \
    --file-prefix "v1"

  [ "$status" -eq 0 ]

  local saved
  saved=$(find "$BATS_TEST_TMPDIR/31337/$CONTRACT_DIR_NAME" -name "v1-*.json" 2>/dev/null | head -1)
  [ -n "$saved" ]
}

@test "--no-save skips file creation" {
  run forge_create "$CONTRACT" \
    --rpc-url "$ANVIL_RPC_URL" \
    --private-key "$ANVIL_PRIVATE_KEY" \
    --save-out "$BATS_TEST_TMPDIR" \
    --no-save

  [ "$status" -eq 0 ]

  local count
  count=$(find "$BATS_TEST_TMPDIR" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 0 ]
}

@test "--save-out writes to custom directory" {
  local custom_dir="$BATS_TEST_TMPDIR/custom"

  run forge_create "$CONTRACT" \
    --rpc-url "$ANVIL_RPC_URL" \
    --private-key "$ANVIL_PRIVATE_KEY" \
    --save-out "$custom_dir"

  [ "$status" -eq 0 ]

  local saved
  saved=$(find "$custom_dir" -name "*.json" 2>/dev/null | head -1)
  [ -n "$saved" ]
  [[ "$saved" == "$custom_dir"* ]]
}

@test "--comment is stored in JSON" {
  run forge_create "$CONTRACT" \
    --rpc-url "$ANVIL_RPC_URL" \
    --private-key "$ANVIL_PRIVATE_KEY" \
    --save-out "$BATS_TEST_TMPDIR" \
    --comment "test deployment"

  [ "$status" -eq 0 ]

  local saved
  saved=$(find "$BATS_TEST_TMPDIR/31337/$CONTRACT_DIR_NAME" -name "*.json" 2>/dev/null | head -1)
  [ -n "$saved" ]
  jq -e '.comment == "test deployment"' "$saved" > /dev/null
}

@test "collision counter: second deploy in same second gets -1 suffix" {
  local deploy_dir="$BATS_TEST_TMPDIR/31337/$CONTRACT_DIR_NAME"
  mkdir -p "$deploy_dir"

  # Pre-seed a file at the current timestamp to force a collision on the next deploy.
  # Anvil deploys complete in <100ms so the deploy will land within the same second.
  local ts ts_formatted
  ts=$(date +%s)
  ts_formatted=$(date -u -r "$ts" "+%Y-%m-%dT%H-%M-%S")
  echo '{"stub":true}' > "$deploy_dir/${ts_formatted}.json"

  run forge_create "$CONTRACT" \
    --rpc-url "$ANVIL_RPC_URL" \
    --private-key "$ANVIL_PRIVATE_KEY" \
    --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]
  [ -f "$deploy_dir/${ts_formatted}-1.json" ]
}

@test "collision counter with --file-prefix gets -1 suffix" {
  local deploy_dir="$BATS_TEST_TMPDIR/31337/$CONTRACT_DIR_NAME"
  mkdir -p "$deploy_dir"

  local ts ts_formatted
  ts=$(date +%s)
  ts_formatted=$(date -u -r "$ts" "+%Y-%m-%dT%H-%M-%S")
  echo '{"stub":true}' > "$deploy_dir/v1-${ts_formatted}.json"

  run forge_create "$CONTRACT" \
    --rpc-url "$ANVIL_RPC_URL" \
    --private-key "$ANVIL_PRIVATE_KEY" \
    --save-out "$BATS_TEST_TMPDIR" \
    --file-prefix "v1"

  [ "$status" -eq 0 ]
  [ -f "$deploy_dir/v1-${ts_formatted}-1.json" ]
}

@test "failed deployment exits non-zero and creates no file" {
  run forge_create "fixtures/Nonexistent.sol:Nonexistent" \
    --rpc-url "$ANVIL_RPC_URL" \
    --private-key "$ANVIL_PRIVATE_KEY" \
    --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -ne 0 ]

  local count
  count=$(find "$BATS_TEST_TMPDIR" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 0 ]
}
