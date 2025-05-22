#!/bin/bash

# Function to display usage information
usage() {
  echo "Usage: forge-create save TX_HASH --commit COMMIT_HASH --contract-path CONTRACT_PATH [options]"
  echo "Required arguments:"
  echo "  TX_HASH           Transaction hash of the deployment"
  echo "  --commit HASH     Commit hash of the source code (must exist in repo)"
  echo "  --contract-path PATH   Path to the contract source file (format: path/to/Contract.sol:ContractName)"
  echo ""
  echo "Options:"
  echo "  --constructor-args ARGS   Constructor arguments (as a string)"
  echo "  --comment TEXT           Comment for the deployment"
  echo "  --rpc-url URL            RPC URL to use (for fetching tx data)"
  echo "  --save-out PATH          Directory to save deployment info (default: ./deployments)"
  exit 1
}

# Function to validate and get full commit hash
validate_commit() {
  local commit="$1"
  local full_commit=""

  # Check length
  if [[ ${#commit} -le 7 ]] || [[ ${#commit} -gt 40 ]]
  then
    echo "Error: Commit hash must be between 8 and 40 characters long." >&2
    return 1
  fi

  # Check if it's a valid hex string
  if ! [[ "${commit}" =~ ^[0-9a-fA-F]+$ ]]
  then
    echo "Error: Commit hash must contain only hexadecimal characters (0-9, a-f, A-F)." >&2
    return 1
  fi

  # Check if it exists in this repo and get the full commit hash
  if ! full_commit=$(git rev-parse --verify "${commit}^{commit}" 2>/dev/null)
  then
    echo "The commit ${commit} does not exist in the current repo. Continue? [Y/n]" >&2
    read -r response
    if [[ "${response}" =~ ^[Nn]$ ]]
    then
      return 1
    fi
    # If the user wants to continue, still use the provided commit hash
    echo "${commit}"
  else
    # Return the full commit hash
    echo "${full_commit}"
  fi
}

# Initialize variables
TX_HASH=""
COMMIT=""
CONTRACT_PATH=""
FILE_CONTRACT_NAME=""
CONSTRUCTOR_ARGS=""
COMMENT=""
RPC_URL=""
SAVE_OUT="./deployments"

# Parse arguments
if [[ $# -lt 1 ]] || [[ "$1" != "save" ]]
then
  usage
fi
shift # Remove 'save' from arguments

# We need at least the TX_HASH, --commit, and --contract-path
if [[ $# -lt 5 ]]
then
  usage
fi

# Parse the transaction hash (first non-flag argument)
if [[ "$1" != "--"* ]]
then
  TX_HASH="$1"
  shift
else
  echo "Error: Transaction hash must be provided as the first argument after 'save'."
  usage
fi

# Parse remaining arguments
while [[ $# -gt 0 ]]
do
  case "$1" in
    --commit)
      if [[ -z "$2" ]] || [[ "$2" == --* ]]
      then
        echo "Error: --commit requires a value."
        exit 1
      fi
      COMMIT="$2"
      shift 2
      ;;
    --contract-path)
      if [[ -z "$2" ]] || [[ "$2" == --* ]]
      then
        echo "Error: --contract-path requires a value."
        exit 1
      fi
      CONTRACT_PATH="$2"
      # Extract the fileContractName (just the filename.sol:ContractName part without the path)
      if [[ "${CONTRACT_PATH}" == *".sol:"* ]]
      then
        FILE_CONTRACT_NAME=$(basename "${CONTRACT_PATH}")
      else
        echo "Error: contract-path must be in the format 'path/to/Contract.sol:ContractName'."
        exit 1
      fi
      shift 2
      ;;
    --constructor-args)
      if [[ -z "$2" ]] || [[ "$2" == --* ]]
      then
        echo "Error: --constructor-args requires a value."
        exit 1
      fi
      CONSTRUCTOR_ARGS="$2"
      shift 2
      ;;
    --comment)
      if [[ -z "$2" ]] || [[ "$2" == --* ]]
      then
        echo "Error: --comment requires a value."
        exit 1
      fi
      COMMENT="$2"
      shift 2
      ;;
    --rpc-url)
      if [[ -z "$2" ]] || [[ "$2" == --* ]]
      then
        echo "Error: --rpc-url requires a value."
        exit 1
      fi
      RPC_URL="$2"
      shift 2
      ;;
    --save-out)
      if [[ -z "$2" ]] || [[ "$2" == --* ]]
      then
        echo "Error: --save-out requires a value."
        exit 1
      fi
      SAVE_OUT="$2"
      shift 2
      ;;
    *)
      echo "Error: Unknown argument '$1'"
      usage
      ;;
  esac
done

# Validate required arguments
if [[ -z "${TX_HASH}" ]]
then
  echo "Error: Transaction hash is required."
  usage
fi

if [[ -z "${COMMIT}" ]]
then
  echo "Error: Commit hash is required (--commit)."
  usage
fi

if [[ -z "${CONTRACT_PATH}" ]]
then
  echo "Error: Contract path is required (--contract-path)."
  usage
fi

# Validate commit hash and get the full hash if available
if ! VALIDATED_COMMIT=$(validate_commit "${COMMIT}")
then
  exit 1
fi
COMMIT="${VALIDATED_COMMIT}"

# Prepare RPC URL argument for cast commands
RPC_ARG=()
if [[ -n "${RPC_URL}" ]]
then
  RPC_ARG=(--rpc-url "${RPC_URL}")
fi

# Get transaction data
echo "Fetching transaction data for ${TX_HASH}..."
if ! TX_DATA=$(cast tx "${TX_HASH}" --json "${RPC_ARG[@]}" 2>/dev/null)
then
  echo "Error: Failed to fetch transaction data. Make sure the transaction hash is valid and the RPC URL is correct."
  exit 1
fi

# Extract necessary information
DEPLOYER=$(echo "${TX_DATA}" | jq -r '.from')
BLOCK_NUMBER=$(echo "${TX_DATA}" | jq -r '.blockNumber')
NONCE=$(echo "${TX_DATA}" | jq -r '.nonce')

# Get block timestamp
echo "Fetching block data for block ${BLOCK_NUMBER}..."
if ! BLOCK_DATA=$(cast block "${BLOCK_NUMBER}" --json "${RPC_ARG[@]}" 2>/dev/null)
then
  echo "Error: Failed to fetch block data."
  exit 1
fi

# Convert timestamp to decimal if it's hex
TIMESTAMP=$(echo "${BLOCK_DATA}" | jq -r '.timestamp')

# Calculate deployed address
echo "Calculating deployed contract address..."
# Convert nonce to decimal if it's hex
NONCE_DEC=$(cast to-dec "${NONCE}" 2>/dev/null)
# Extract just the address (last word) from the output
if ! CA_RESULT=$(cast ca "${DEPLOYER}" --nonce "${NONCE_DEC}" "${RPC_ARG[@]}" 2>/dev/null)
then
  echo "Error: Failed to calculate contract address."
  exit 1
fi
DEPLOYED_TO=$(echo "${CA_RESULT}" | awk '{print $NF}')

if [[ -z "${DEPLOYED_TO}" ]]
then
  echo "Error: Failed to calculate contract address."
  exit 1
fi

# Convert timestamp to ISO8601 format (without ms) for filename
# First convert to decimal if it's hex
TIMESTAMP_DEC=$(cast to-dec "${TIMESTAMP}" 2>/dev/null)
RAW_FILE_NAME=$(date -u -r "${TIMESTAMP_DEC}" "+%Y-%m-%dT%H:%M:%S")

# Determine the chainId and convert to decimal
CHAIN_ID=31337
if [[ -n "${RPC_URL}" ]]
then
  if CHAIN_ID_HEX=$(cast chain-id "${RPC_ARG[@]}" 2>/dev/null)
  then
    CHAIN_ID=$(cast to-dec "${CHAIN_ID_HEX}" 2>/dev/null || echo "31337")
  fi
fi

# Create JSON array from constructor args
CONSTRUCTOR_ARGS_JSON="[]"
if [[ -n "${CONSTRUCTOR_ARGS}" ]]
then
  # Parse the constructor args string into an array
  # This assumes the string is a space-separated list of arguments
  read -ra CONSTRUCTOR_ARGS_ARRAY <<<"${CONSTRUCTOR_ARGS}"
  CONSTRUCTOR_ARGS_JSON="["
  for i in "${!CONSTRUCTOR_ARGS_ARRAY[@]}"
  do
    if [[ "${i}" -gt 0 ]]
    then
      CONSTRUCTOR_ARGS_JSON="${CONSTRUCTOR_ARGS_JSON},"
    fi
    CONSTRUCTOR_ARGS_JSON="${CONSTRUCTOR_ARGS_JSON}\"${CONSTRUCTOR_ARGS_ARRAY[${i}]}\""
  done
  CONSTRUCTOR_ARGS_JSON="${CONSTRUCTOR_ARGS_JSON}]"
fi

# Create the final JSON output with the same order as in forge-create-create.sh
FINAL_OUTPUT=$(jq -n \
  --arg deployer "${DEPLOYER}" \
  --arg deployedTo "${DEPLOYED_TO}" \
  --arg txHash "${TX_HASH}" \
  --arg commit "${COMMIT}" \
  --argjson timestamp "${TIMESTAMP_DEC}" \
  --argjson chainId "${CHAIN_ID}" \
  --arg contractPath "${CONTRACT_PATH}" \
  --argjson constructorArgs "${CONSTRUCTOR_ARGS_JSON}" \
  --arg comment "${COMMENT}" \
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

# Create the directory structure: <out directory>/chain-id/fileContractName
FINAL_DIR="${SAVE_OUT%/}/${CHAIN_ID}/${FILE_CONTRACT_NAME}"
mkdir -p "${FINAL_DIR}"

# Determine the filename according to the algorithm
# 1. Calculate rawFileName
FILE_NAME="${RAW_FILE_NAME}.json"
FILE_BASE="${FINAL_DIR}/${RAW_FILE_NAME}"
FILE_PATH="${FILE_BASE}.json"

# 2. Check if such file already exists
if [[ -f "${FILE_PATH}" ]]
then
  # 3. Get the counter numbers from all matching files
  HIGHEST_COUNTER=0

  # Use ls with a pattern and grep to extract all counters
  for file in "${FILE_BASE}"-*.json "${FILE_BASE}".json
  do
    if [[ -f "${file}" ]]
    then
      # Extract the counter from the filename
      if [[ "${file}" == *"-"*".json" ]]
      then
        # Extract just the number part before .json extension
        counter_part=$(basename "${file}" .json)
        counter=${counter_part##*-}

        # Check if it's a number and update highest counter
        if [[ "${counter}" =~ ^[0-9]+$ ]] && [[ "${counter}" -gt "${HIGHEST_COUNTER}" ]]
        then
          HIGHEST_COUNTER=${counter}
        fi
      fi
    fi
  done

  # 4. Increment the highest counter
  NEW_COUNTER=$((HIGHEST_COUNTER + 1))

  # 5. Generate new filename with counter
  FILE_NAME="${RAW_FILE_NAME}-${NEW_COUNTER}.json"
fi

# Create the full save path
SAVE_PATH="${FINAL_DIR}/${FILE_NAME}"

# Save to the timestamped file in the specified directory
echo "${FINAL_OUTPUT}" >"${SAVE_PATH}"

echo "Storing deployment result to: ${SAVE_PATH}"
