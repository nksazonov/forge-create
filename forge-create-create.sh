#!/bin/bash

# Check if there are any arguments
if [[ $# -eq 0 ]]
then
  echo "Usage: forge-create-create.sh [script options] [forge create arguments]"
  echo "Script options:"
  echo "  --no-save          Don't save output to JSON file"
  echo "  --save-out PATH    Path where to save the chain and contract directories with the JSON file (default: ./deployments)"
  echo "  --comment TEXT     Add a comment to the stored JSON file"
  exit 1
fi

# Initialize variables
RPC_URL=""
JSON_FLAG_PRESENT=false
FORGE_ARGS=()
CONSTRUCTOR_ARGS=()
CONTRACT_PATH=""
FILE_CONTRACT_NAME=""
NO_SAVE=false
SAVE_OUT="./deployments"
COMMENT=""

# First pass: identify script-specific flags and check if --json is already present
i=0
while [[ "${i}" -lt $# ]]
do
  i=$((i + 1))
  arg="${!i}"

  # Handle script-specific flags
  if [[ "${arg}" == "--no-save" ]]
  then
    NO_SAVE=true
  elif [[ "${arg}" == "--save-out" ]] && [[ "${i}" -lt $# ]]
  then
    i=$((i + 1))
    SAVE_OUT="${!i}"
  elif [[ "${arg}" == "--comment" ]] && [[ "${i}" -lt $# ]]
  then
    i=$((i + 1))
    COMMENT="${!i}"
  # Check for --json flag
  elif [[ "${arg}" == "--json" ]]
  then
    JSON_FLAG_PRESENT=true
  fi
done

# Second pass: build the forge arguments list correctly
i=0
while [[ "${i}" -lt $# ]]
do
  i=$((i + 1))
  arg="${!i}"

  # Skip script-specific flags
  if [[ "${arg}" == "--no-save" ]]
  then
    continue
  elif [[ "${arg}" == "--save-out" ]] && [[ "${i}" -lt $# ]]
  then
    i=$((i + 1))
    continue
  elif [[ "${arg}" == "--comment" ]] && [[ "${i}" -lt $# ]]
  then
    i=$((i + 1))
    continue
  fi

  # Extract RPC URL if needed but still pass it to forge
  if [[ ${arg} == --rpc-url=* ]]
  then
    RPC_URL="${arg#*=}"
  elif [[ "${arg}" == "--rpc-url" ]] && [[ "${i}" -lt $# ]]
  then
    i=$((i + 1))
    RPC_URL="${!i}"
    i=$((i-1))  # Go back since we'll handle this in the special case below
  fi

  # Extract contract path from argument containing .sol:
  if [[ "${arg}" == *".sol:"* ]]
  then
    CONTRACT_PATH="${arg}"
    # Extract the fileContractName (just the filename.sol:ContractName part without the path)
    FILE_CONTRACT_NAME=$(basename "${CONTRACT_PATH}")
  fi

  # Handle constructor arguments special case
  if [[ "${arg}" == "--constructor-args" ]]
  then
    FORGE_ARGS+=("${arg}")

    # Collect all following arguments until the next option flag
    while [[ "${i}" -lt $# ]]
    do
      i=$((i + 1))
      next_arg="${!i}"

      # Stop if we encounter another option
      if [[ "${next_arg}" == --* ]]
      then
        i=$((i - 1)) # Go back one as we'll increment again in the outer loop
        break
      fi

      # Add to constructor args array and forge args
      CONSTRUCTOR_ARGS+=("${next_arg}")
      FORGE_ARGS+=("${next_arg}")
    done
  # Special handling for --rpc-url to ensure it and its value are captured
  elif [ "$arg" == "--rpc-url" ] && [ $i -lt $# ]; then
    FORGE_ARGS+=("$arg")
    i=$((i+1))
    FORGE_ARGS+=("${!i}")
  else
    # Add regular arguments to forge args
    FORGE_ARGS+=("${arg}")
  fi
done

# Build the final command array with --json in the correct position if needed
FINAL_ARGS=("forge" "create")

# Only add --json flag if not present AND we need to save output
if [[ "${JSON_FLAG_PRESENT}" = false ]] && [[ "${NO_SAVE}" = false ]]
then
  FINAL_ARGS+=("--json")
fi

# Add all other arguments
for arg in "${FORGE_ARGS[@]}"
do
  FINAL_ARGS+=("${arg}")
done

# Execute forge create with collected arguments
OUTPUT=$("${FINAL_ARGS[@]}" 2>&1)
DEPLOY_STATUS=$?

# If deployment failed, just output the original error and exit
if [[ "${DEPLOY_STATUS}" -ne 0 ]]
then
  echo "${OUTPUT}"
  exit "${DEPLOY_STATUS}"
fi

# If --no-save flag is set, just echo the output and exit
if [[ "${NO_SAVE}" = true ]]
then
  echo "${OUTPUT}"
  exit 0
fi

COMMIT=$(git rev-parse HEAD)

TIMESTAMP=$(date +%s)

# Convert timestamp to ISO8601 format (without ms) for filename
RAW_FILE_NAME=$(date -u -r "${TIMESTAMP}" "+%Y-%m-%dT%H:%M:%S")

# Determine the chainId
if [[ -n "${RPC_URL}" ]]
then
  if ! CHAIN_ID=$(cast chain-id --rpc-url "${RPC_URL}" 2>/dev/null)
  then
    # Fallback if cast chain-id fails
    CHAIN_ID=31337
  fi
else
  CHAIN_ID=31337
fi

# Create JSON array from constructor args
CONSTRUCTOR_ARGS_JSON="[]"
if [[ ${#CONSTRUCTOR_ARGS[@]} -gt 0 ]]
then
  CONSTRUCTOR_ARGS_JSON="["
  for i in "${!CONSTRUCTOR_ARGS[@]}"
  do
    if [[ "${i}" -gt 0 ]]
    then
      CONSTRUCTOR_ARGS_JSON="${CONSTRUCTOR_ARGS_JSON},"
    fi
    CONSTRUCTOR_ARGS_JSON="${CONSTRUCTOR_ARGS_JSON}\"${CONSTRUCTOR_ARGS[${i}]}\""
  done
  CONSTRUCTOR_ARGS_JSON="${CONSTRUCTOR_ARGS_JSON}]"
fi

# Add the additional fields to the output JSON
FINAL_OUTPUT=$(echo "${OUTPUT}" | jq \
  --arg commit "${COMMIT}" \
  --arg timestamp "${TIMESTAMP}" \
  --arg chainId "${CHAIN_ID}" \
  --arg contractPath "${CONTRACT_PATH}" \
  --arg comment "${COMMENT}" \
  --argjson constructorArgs "${CONSTRUCTOR_ARGS_JSON}" \
  '. + {
    commit: $commit,
    timestamp: $timestamp | tonumber,
    chainId: $chainId | tonumber,
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

SAVE_PATH="${FINAL_DIR}/${FILE_NAME}"

echo "${FINAL_OUTPUT}" >"${SAVE_PATH}"

echo "Storing deployment result to: ${SAVE_PATH}"
echo
echo "${OUTPUT}"
