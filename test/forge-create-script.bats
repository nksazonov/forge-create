#!/usr/bin/env bats

FORGE_CREATE="$BATS_TEST_DIRNAME/../forge-create.sh"
FIXTURE="$BATS_TEST_DIRNAME/fixtures/run-script-fixture.json"

# Four transactions in the fixture (three deployments, one CALL):
#
#   Counter.script  — Counter.sol EXISTS under fixtures/  → contractPath resolves to .sol path
#                     directory: Counter.sol_Counter
#
#   Vault           — no dot in name, Vault.sol NOT present → contractPath falls back to "Vault"
#                     directory: Vault
#
#   RemoteEngine.deploy — dot in name, RemoteEngine.sol NOT present → prefix "RemoteEngine" used
#                         directory: RemoteEngine
#
#   CALL (initialize)   — contractAddress is null → skipped

COUNTER_DIR="Counter.sol_Counter"
VAULT_DIR="Vault"
REMOTE_DIR="RemoteEngine"
CHAIN_ID="31337"

# Run save-script from the test/ directory so find can locate Counter.sol under fixtures/.
save_script() {
  (cd "$BATS_TEST_DIRNAME" && "$FORGE_CREATE" save-script "$@")
}

# ---------------------------------------------------------------------------
# Core behaviour
# ---------------------------------------------------------------------------

@test "happy path: saves one artifact per deployment tx" {
  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]

  local count
  count=$(find "$BATS_TEST_TMPDIR" -name "*.json" | wc -l | tr -d ' ')
  [ "$count" -eq 3 ]
}

@test "summary line reports saved and skipped counts" {
  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Saved 3 artifact(s), skipped 1 non-deployment transaction(s)."* ]]
}

@test "CALL tx with null contractAddress is skipped" {
  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]

  local found
  found=$(grep -rl "0xcccc" "$BATS_TEST_TMPDIR" 2>/dev/null | wc -l | tr -d ' ')
  [ "$found" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Artifact field correctness
# ---------------------------------------------------------------------------

@test "artifact JSON fields are correct" {
  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]

  local saved
  saved=$(find "$BATS_TEST_TMPDIR/$CHAIN_ID/$COUNTER_DIR" -name "*.json" | head -1)
  [ -n "$saved" ]

  jq -e '.deployer == "0xf8bedb0aba14833e95f29e760487c3d34bc4ec64"' "$saved" > /dev/null
  jq -e '.deployedTo == "0x1111111111111111111111111111111111111111"' "$saved" > /dev/null
  jq -e '.transactionHash == "0xaaaa0000000000000000000000000000000000000000000000000000000000aa"' "$saved" > /dev/null
  jq -e '.commit == "abcdef12"' "$saved" > /dev/null
  jq -e '.timestamp == 1747000000' "$saved" > /dev/null
  jq -e '.chainId == 31337' "$saved" > /dev/null
  jq -e '.constructorArgs == []' "$saved" > /dev/null
}

@test "timestamp is stored in seconds (ms divided by 1000)" {
  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]

  # fixture timestamp is 1747000000000 ms → 1747000000 s; check all three artifacts agree
  while IFS= read -r f; do
    jq -e '.timestamp == 1747000000' "$f" > /dev/null
  done < <(find "$BATS_TEST_TMPDIR" -name "*.json")
}

@test "chainId is stored as integer, not string" {
  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]

  while IFS= read -r f; do
    jq -e '.chainId | type == "number"' "$f" > /dev/null
  done < <(find "$BATS_TEST_TMPDIR" -name "*.json")
}

@test "constructorArgs array is stored correctly when present" {
  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]

  local saved
  saved=$(find "$BATS_TEST_TMPDIR/$CHAIN_ID/$VAULT_DIR" -name "*.json" | head -1)
  [ -n "$saved" ]

  jq -e '.constructorArgs == ["0x1111111111111111111111111111111111111111","100"]' "$saved" > /dev/null
}

@test "constructorArgs is empty array when null in run file" {
  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]

  local saved
  saved=$(find "$BATS_TEST_TMPDIR/$CHAIN_ID/$COUNTER_DIR" -name "*.json" | head -1)
  [ -n "$saved" ]

  jq -e '.constructorArgs == []' "$saved" > /dev/null
}

# ---------------------------------------------------------------------------
# contractName prefix extraction
# ---------------------------------------------------------------------------

@test "contractName with dot: prefix before dot used as directory" {
  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]

  # "Counter.script" → Counter, not "Counter.script"
  [ -d "$BATS_TEST_TMPDIR/$CHAIN_ID/$COUNTER_DIR" ]
  [ ! -d "$BATS_TEST_TMPDIR/$CHAIN_ID/Counter.script" ]
}

@test "contractName without dot: full name used as directory" {
  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]

  [ -d "$BATS_TEST_TMPDIR/$CHAIN_ID/$VAULT_DIR" ]
}

@test "contractName with dot, no local sol: prefix used as directory" {
  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]

  # "RemoteEngine.deploy" → RemoteEngine (no sol file present)
  [ -d "$BATS_TEST_TMPDIR/$CHAIN_ID/$REMOTE_DIR" ]
  [ ! -d "$BATS_TEST_TMPDIR/$CHAIN_ID/RemoteEngine.deploy" ]
}

# ---------------------------------------------------------------------------
# contractPath resolution
# ---------------------------------------------------------------------------

@test "contractPath resolves to .sol path when file exists locally" {
  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]

  local saved
  saved=$(find "$BATS_TEST_TMPDIR/$CHAIN_ID/$COUNTER_DIR" -name "*.json" | head -1)
  [ -n "$saved" ]

  # Counter.sol exists under fixtures/ → contractPath ends with .sol:Counter
  jq -e '.contractPath | test("\\.sol:Counter$")' "$saved" > /dev/null
}

@test "contractPath falls back to name when .sol not found (no dot in name)" {
  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]

  local saved
  saved=$(find "$BATS_TEST_TMPDIR/$CHAIN_ID/$VAULT_DIR" -name "*.json" | head -1)
  [ -n "$saved" ]

  jq -e '.contractPath == "Vault"' "$saved" > /dev/null
}

@test "contractPath falls back to name prefix when .sol not found (dot in name)" {
  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]

  local saved
  saved=$(find "$BATS_TEST_TMPDIR/$CHAIN_ID/$REMOTE_DIR" -name "*.json" | head -1)
  [ -n "$saved" ]

  # "RemoteEngine.deploy" → no sol found → contractPath is "RemoteEngine", not "RemoteEngine.deploy"
  jq -e '.contractPath == "RemoteEngine"' "$saved" > /dev/null
}

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------

@test "--comment is stored in every artifact" {
  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR" --comment "initial deploy"

  [ "$status" -eq 0 ]

  while IFS= read -r f; do
    jq -e '.comment == "initial deploy"' "$f" > /dev/null
  done < <(find "$BATS_TEST_TMPDIR" -name "*.json")
}

@test "--comment defaults to empty string when omitted" {
  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]

  while IFS= read -r f; do
    jq -e '.comment == ""' "$f" > /dev/null
  done < <(find "$BATS_TEST_TMPDIR" -name "*.json")
}

@test "--file-prefix prepends to every artifact filename" {
  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR" --file-prefix "v2"

  [ "$status" -eq 0 ]

  local count
  count=$(find "$BATS_TEST_TMPDIR" -name "v2-*.json" | wc -l | tr -d ' ')
  [ "$count" -eq 3 ]
}

@test "--save-out writes to custom directory" {
  local custom="$BATS_TEST_TMPDIR/custom-out"

  run save_script "$FIXTURE" --save-out "$custom"

  [ "$status" -eq 0 ]

  local count
  count=$(find "$custom" -name "*.json" | wc -l | tr -d ' ')
  [ "$count" -eq 3 ]
}

# ---------------------------------------------------------------------------
# Filename collision
# ---------------------------------------------------------------------------

@test "collision counter: second run adds -1 suffix to all artifacts" {
  save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]

  local count
  count=$(find "$BATS_TEST_TMPDIR" -name "*-1.json" | wc -l | tr -d ' ')
  [ "$count" -eq 3 ]
}

@test "collision counter increments: third run adds -2 suffix" {
  save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"
  save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -eq 0 ]

  local count
  count=$(find "$BATS_TEST_TMPDIR" -name "*-2.json" | wc -l | tr -d ' ')
  [ "$count" -eq 3 ]
}

@test "collision counter works correctly with --file-prefix" {
  save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR" --file-prefix "v1"

  run save_script "$FIXTURE" --save-out "$BATS_TEST_TMPDIR" --file-prefix "v1"

  [ "$status" -eq 0 ]

  local count
  count=$(find "$BATS_TEST_TMPDIR" -name "v1-*-1.json" | wc -l | tr -d ' ')
  [ "$count" -eq 3 ]
}

# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------

@test "error: run file not found" {
  run save_script "/nonexistent/path/run.json" --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"File not found"* ]]
}

@test "error: no run file argument" {
  run save_script --save-out "$BATS_TEST_TMPDIR"

  [ "$status" -ne 0 ]
}
