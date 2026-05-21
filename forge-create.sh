#!/bin/bash

# Version constant
VERSION="v0.3.1"

# Function to display usage information
display_usage() {
  echo "Usage: forge-create [command] [options]"
  echo ""
  echo "Commands:"
  echo "  <default>        Run forge create with deployment info saving capabilities"
  echo "  save             Save deployment info for an existing transaction"
  echo "  save-script      Batch-save artifacts from a Foundry script run file"
  echo "  --version, -v    Show version information"
  echo ""
  echo "For 'create' command options:"
  echo "  forge-create.sh [script options] [forge create arguments]"
  echo "  Script options:"
  echo "    --no-save          Don't save output to JSON file"
  echo "    --save-out PATH    Path where to save JSON files (default: ./deployments)"
  echo "    --comment TEXT     Add a comment to the stored JSON file"
  echo "    --file-prefix TEXT Prefix to prepend to the deployment file name"
  echo ""
  echo "For 'save' command options:"
  echo "  forge-create.sh save TX_HASH --commit COMMIT_HASH --contract-path CONTRACT_PATH [options]"
  echo "  Required arguments:"
  echo "    TX_HASH               Transaction hash of the deployment"
  echo "    --commit HASH         Commit hash of the source code (must exist in repo)"
  echo "    --contract-path PATH  Path to the contract source (format: path/to/Contract.sol:ContractName)"
  echo "  Options:"
  echo "    --constructor-args ARGS  Constructor arguments (as a string)"
  echo "    --comment TEXT           Comment for the deployment"
  echo "    --rpc-url URL            RPC URL to use (for fetching tx data)"
  echo "    --save-out PATH          Directory to save deployment info (default: ./deployments)"
  echo "    --file-prefix TEXT       Prefix to prepend to the deployment file name"
  echo ""
  echo "For 'save-script' command options:"
  echo "  forge-create.sh save-script <run-file> [options]"
  echo "  Required arguments:"
  echo "    <run-file>            Path to a Foundry script run artifact JSON file"
  echo "  Options:"
  echo "    --save-out PATH       Directory to save deployment artifacts (default: ./deployments)"
  echo "    --file-prefix TEXT    Prefix to prepend to each deployment filename"
  echo "    --comment TEXT        Comment added to every saved artifact"
  exit 1
}

# Make sure the helper scripts exist and are executable
REALPATH_RESULT=$(realpath "$0")
SCRIPT_DIR="$(dirname "${REALPATH_RESULT}")"
CREATE_SCRIPT="${SCRIPT_DIR}/forge-create-create.sh"
SAVE_SCRIPT="${SCRIPT_DIR}/forge-create-save.sh"
SCRIPT_SCRIPT="${SCRIPT_DIR}/forge-create-script.sh"

if [[ ! -f "${CREATE_SCRIPT}" ]]
then
  echo "Error: Could not find create script at ${CREATE_SCRIPT}"
  exit 1
fi

if [[ ! -f "${SAVE_SCRIPT}" ]]
then
  echo "Error: Could not find save script at ${SAVE_SCRIPT}"
  exit 1
fi

if [[ ! -f "${SCRIPT_SCRIPT}" ]]
then
  echo "Error: Could not find script at ${SCRIPT_SCRIPT}"
  exit 1
fi

# Make them executable if they aren't already
chmod +x "${CREATE_SCRIPT}" 2>/dev/null
chmod +x "${SAVE_SCRIPT}" 2>/dev/null
chmod +x "${SCRIPT_SCRIPT}" 2>/dev/null

# If no arguments provided, show usage
if [[ $# -eq 0 ]]
then
  display_usage
fi

# Check for the command (first argument)
if [[ "$1" = "save" ]]
then
  # Pass all arguments to the save script
  "${SAVE_SCRIPT}" "$@"
  exit $?
elif [[ "$1" = "save-script" ]]
then
  "${SCRIPT_SCRIPT}" "$@"
  exit $?
elif [[ "$1" = "help" ]] || [[ "$1" = "--help" ]] || [[ "$1" = "-h" ]]
then
  display_usage
elif [[ "$1" = "--version" ]] || [[ "$1" = "-v" ]]
then
  echo "${VERSION}"
  exit 0
else
  # Pass all arguments to the create script
  "${CREATE_SCRIPT}" "$@"
  exit $?
fi
