#!/bin/bash

usage() {
  echo "Usage: forge-create save-script <run-file> [options]"
  echo "Required arguments:"
  echo "  <run-file>           Path to a Foundry script run artifact JSON file"
  echo ""
  echo "Options:"
  echo "  --save-out PATH      Directory to save deployment artifacts (default: ./deployments)"
  echo "  --file-prefix TEXT   Prefix to prepend to each deployment filename"
  echo "  --comment TEXT       Comment added to every saved artifact"
  exit 1
}

# Resolve a contract name to a .sol file path under CWD.
# Outputs "<path>/<Name>.sol:<Name>" if found, or "<Name>" as fallback.
resolve_contract_path() {
  local name="$1"
  local sol_file
  sol_file=$(find . -name "${name}.sol" \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/out/*" \
    -not -path "*/cache/*" \
    2>/dev/null | head -1)

  if [[ -n "$sol_file" ]]; then
    echo "${sol_file#./}:${name}"
  else
    echo "$name"
  fi
}

# Same collision algorithm used by forge-create-save.sh.
# Outputs the final filename (basename only, including .json extension).
resolve_filename() {
  local dir="$1"
  local prefixed_base="$2"   # e.g. "v1-2026-05-19T10-00-00" or "2026-05-19T10-00-00"

  local file_path="${dir}/${prefixed_base}.json"
  if [[ ! -f "$file_path" ]]; then
    echo "${prefixed_base}.json"
    return
  fi

  local highest=0
  for f in "${dir}/${prefixed_base}"-*.json; do
    [[ -f "$f" ]] || continue
    local base
    base=$(basename "$f" .json)
    local counter="${base##*-}"
    if [[ "$counter" =~ ^[0-9]+$ ]] && [[ "$counter" -gt "$highest" ]]; then
      highest=$counter
    fi
  done

  echo "${prefixed_base}-$(( highest + 1 )).json"
}

# --- Argument parsing ---

RUN_FILE=""
SAVE_OUT="./deployments"
FILE_PREFIX=""
COMMENT=""

if [[ $# -lt 1 ]] || [[ "$1" == "save-script" && $# -lt 2 ]]; then
  usage
fi

# Strip the "save-script" dispatcher token if present
if [[ "$1" == "save-script" ]]; then
  shift
fi

# First positional argument is the run file
if [[ "$1" != "--"* ]]; then
  RUN_FILE="$1"
  shift
else
  echo "Error: run-file must be provided as the first argument after 'save-script'."
  usage
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --save-out)
      [[ -z "$2" || "$2" == --* ]] && { echo "Error: --save-out requires a value."; exit 1; }
      SAVE_OUT="$2"; shift 2 ;;
    --file-prefix)
      [[ -z "$2" || "$2" == --* ]] && { echo "Error: --file-prefix requires a value."; exit 1; }
      FILE_PREFIX="$2"; shift 2 ;;
    --comment)
      [[ -z "$2" || "$2" == --* ]] && { echo "Error: --comment requires a value."; exit 1; }
      COMMENT="$2"; shift 2 ;;
    *)
      echo "Error: Unknown argument '$1'"; usage ;;
  esac
done

if [[ -z "$RUN_FILE" ]]; then
  echo "Error: run-file is required."
  usage
fi

if [[ ! -f "$RUN_FILE" ]]; then
  echo "Error: File not found: $RUN_FILE"
  exit 1
fi

# --- Read top-level fields ---

COMMIT=$(jq -r '.commit // empty' "$RUN_FILE")
CHAIN_ID=$(jq -r '.chain // empty' "$RUN_FILE")
TIMESTAMP_MS=$(jq -r '.timestamp // empty' "$RUN_FILE")

if [[ -z "$COMMIT" || -z "$CHAIN_ID" || -z "$TIMESTAMP_MS" ]]; then
  echo "Error: run file is missing required top-level fields (commit, chain, timestamp)."
  exit 1
fi

TIMESTAMP_S=$(( TIMESTAMP_MS / 1000 ))
RAW_FILE_NAME=$(date -u -r "${TIMESTAMP_S}" "+%Y-%m-%dT%H-%M-%S")

# --- Iterate over transactions ---

TX_COUNT=$(jq '.transactions | length' "$RUN_FILE")
SAVED=0
SKIPPED=0

for (( i=0; i<TX_COUNT; i++ )); do
  TX=$(jq ".transactions[$i]" "$RUN_FILE")

  CONTRACT_ADDRESS=$(echo "$TX" | jq -r '.contractAddress // empty')
  if [[ -z "$CONTRACT_ADDRESS" ]]; then
    (( SKIPPED++ ))
    continue
  fi

  TX_HASH=$(echo "$TX" | jq -r '.hash // empty')
  if [[ -z "$TX_HASH" ]]; then
    (( SKIPPED++ ))
    continue
  fi

  TX_TO=$(echo "$TX" | jq -r '.transaction.to // empty')
  if [[ -z "$TX_TO" ]]; then
    (( SKIPPED++ ))
    continue
  fi

  DEPLOYER=$(echo "$TX" | jq -r '.transaction.from')
  CONSTRUCTOR_ARGS_JSON=$(echo "$TX" | jq -c '.arguments // []')

  # Extract contract name prefix (before the first ".")
  FULL_CONTRACT_NAME=$(echo "$TX" | jq -r '.contractName')
  CONTRACT_NAME="${FULL_CONTRACT_NAME%%.*}"

  # Resolve contractPath
  CONTRACT_PATH=$(resolve_contract_path "$CONTRACT_NAME")

  # Derive FILE_CONTRACT_NAME using the same convention as forge-create-create.sh
  FILE_CONTRACT_NAME=$(basename "$CONTRACT_PATH" | tr ':' '_')

  # Build the artifact JSON
  ARTIFACT=$(jq -n \
    --arg deployer "$DEPLOYER" \
    --arg deployedTo "$CONTRACT_ADDRESS" \
    --arg txHash "$TX_HASH" \
    --arg commit "$COMMIT" \
    --argjson timestamp "$TIMESTAMP_S" \
    --argjson chainId "$CHAIN_ID" \
    --arg contractPath "$CONTRACT_PATH" \
    --argjson constructorArgs "$CONSTRUCTOR_ARGS_JSON" \
    --arg comment "$COMMENT" \
    '{
      deployer: $deployer,
      deployedTo: $deployedTo,
      transactionHash: $txHash,
      commit: $commit,
      timestamp: $timestamp,
      chainId: $chainId,
      contractPath: $contractPath,
      constructorArgs: $constructorArgs,
      comment: $comment
    }')

  # Determine output directory and filename
  FINAL_DIR="${SAVE_OUT%/}/${CHAIN_ID}/${FILE_CONTRACT_NAME}"
  mkdir -p "$FINAL_DIR"

  if [[ -n "$FILE_PREFIX" ]]; then
    PREFIXED_BASE="${FILE_PREFIX}-${RAW_FILE_NAME}"
  else
    PREFIXED_BASE="${RAW_FILE_NAME}"
  fi

  FILE_NAME=$(resolve_filename "$FINAL_DIR" "$PREFIXED_BASE")
  SAVE_PATH="${FINAL_DIR}/${FILE_NAME}"

  echo "$ARTIFACT" > "$SAVE_PATH"
  echo "Storing deployment result to: ${SAVE_PATH}"
  (( SAVED++ ))
done

echo "Saved ${SAVED} artifact(s), skipped ${SKIPPED} non-deployment transaction(s)."
