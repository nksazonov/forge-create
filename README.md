# forge-create

A wrapper around Foundry's `forge create` command that automatically saves deployment information to organized JSON files.

## Features

- Extends the standard `forge create` functionality to save deployment information
- Organizes deployments by chain ID and contract name
- Records contract deployment metadata:
  - Transaction hash
  - Contract address
  - Deployer address
  - Constructor arguments
  - Git commit hash
  - Deployment timestamp
  - Contract path
- Supports saving deployment information for existing deployments
- Batch-saves artifacts from Foundry script run files (no blockchain calls needed)

## Installation

```bash
brew install nksazonov/forge-create/forge-create
```

Or via tap:

```bash
brew tap nksazonov/forge-create
brew install forge-create
```

## Usage

### Creating and Saving a New Deployment

Use `forge-create` as a drop-in replacement for `forge create`:

```bash
forge-create src/MyContract.sol_MyContract --rpc-url <your-rpc-url> --private-key <your-private-key>
```

Additional options specific to `forge-create`:

```txt
--no-save            Don't save output to JSON file
--save-out PATH      Path where to save the JSON files (default: ./deployments)
--comment "TEXT"     Add a comment to the stored JSON file
--file-prefix "TEXT" Prefix to prepend to the deployment file name
```

Example with all options:

```txt
forge-create src/MyContract.sol:MyContract \
  --rpc-url https://eth-mainnet.example.com \
  --private-key 0xYourPrivateKey \
  --constructor-args 123 "string arg" \
  --save-out ./my-deployments \
  --comment "Initial deployment to mainnet"
```

### Saving Information for an Existing Deployment

You can save deployment information for contracts that were deployed in the past:

```txt
forge-create save <tx-hash> \
  --commit <commit-hash> \
  --contract-path src/MyContract.sol:MyContract \
  --rpc-url <your-rpc-url> \
  --constructor-args "123 \"string arg\"" \
  --comment "Saving existing deployment info" \
  --save-out ./my-deployments
```

Required arguments:

- `TX_HASH` - Transaction hash of the deployment
- `--commit HASH` - Git commit hash of the source code when deployed
- `--contract-path PATH` - Path to the contract source file (format: path/to/Contract.sol:ContractName)

Optional arguments:

- `--constructor-args ARGS` - Constructor arguments (as a string)
- `--comment TEXT` - Comment for the deployment
- `--rpc-url URL` - RPC URL to use (for fetching tx data)
- `--save-out PATH` - Directory to save deployment info (default: ./deployments)
- `--file-prefix TEXT` - Prefix to prepend to the deployment file name

### Saving Artifacts from a Foundry Script Run

When you deploy multiple contracts with a Foundry script, the run artifact file
(`broadcast/<Script>.s.sol/<chainId>/run-latest.json`) contains everything needed to
save deployment records — no blockchain calls required:

```bash
forge-create save-script broadcast/Deploy.s.sol/80002/run-latest.json \
  --save-out ./deployments \
  --file-prefix v1 \
  --comment "mainnet deploy"
```

This reads every CREATE/CREATE2 transaction from the file and saves one artifact per
contract. CALL transactions are skipped automatically.

Optional arguments:

- `--save-out PATH` - Directory to save deployment artifacts (default: ./deployments)
- `--file-prefix TEXT` - Prefix to prepend to each deployment filename
- `--comment TEXT` - Comment added to every saved artifact

**Contract path resolution:** For each deployed contract, `save-script` searches for a
matching `.sol` file in the current directory. If found, `contractPath` is stored as
`src/MyContract.sol:MyContract`; otherwise it falls back to just the contract name.

Example output for a 5-contract deploy:

```
Storing deployment result to: deployments/80002/ChannelEngine/v1-2026-03-07T14-28-35.json
Storing deployment result to: deployments/80002/EscrowWithdrawalEngine/v1-2026-03-07T14-28-35.json
Storing deployment result to: deployments/80002/EscrowDepositEngine/v1-2026-03-07T14-28-35.json
Storing deployment result to: deployments/80002/ECDSAValidator/v1-2026-03-07T14-28-35.json
Storing deployment result to: deployments/80002/ChannelHub/v1-2026-03-07T14-28-35.json
Saved 5 artifact(s), skipped 0 non-deployment transaction(s).
```

## File Structure

Deployment files are organized by chain ID and contract name:

```bash
deployments/
├── 1/                        # Ethereum Mainnet (Chain ID: 1)
│   └── MyContract.sol_MyContract/
│       └── 2025-05-21T12-00-00.json
├── 5/                        # Goerli Testnet (Chain ID: 5)
│   └── MyContract.sol_MyContract/
│       ├── 2025-05-22T15-30-42.json
│       └── 2025-05-22T15-30-42-1.json  # Counter added for same-second deploys
└── 31337/                    # Local Anvil Chain (Chain ID: 31337)
    └── MyContract.sol_MyContract/
        └── 2025-05-23T10-15-00.json
```

Using `--file-prefix v1` produces files like `v1-2025-05-21T12-00-00.json`.

## JSON File Format

Each deployment is saved as a JSON file with the following structure:

```json
{
  "deployer": "0x123...",
  "deployedTo": "0x456...",
  "transactionHash": "0x789...",
  "commit": "abcdef1234567890",
  "timestamp": 1672567200,
  "chainId": 1,
  "contractPath": "src/MyContract.sol:MyContract",
  "constructorArgs": ["123", "string arg"],
  "comment": "Initial deployment to mainnet"
}
```

## Requirements

- [Foundry](https://github.com/foundry-rs/foundry) - For `forge` and `cast` commands
- [jq](https://stedolan.github.io/jq/) - For JSON processing

## Testing

Tests use [BATS](https://github.com/bats-core/bats-core) (≥1.3) and deploy a real contract against a local Anvil instance.

Install BATS:

```bash
brew install bats-core
```

Run the tests:

```bash
bats test/forge-create.bats       # create/save tests (requires Anvil)
bats test/forge-create-script.bats  # save-script tests (no Anvil needed)
```

The `forge-create.bats` suite starts and stops Anvil automatically. Each test gets
isolated chain state via `anvil_snapshot`/`anvil_revert`.

The `forge-create-script.bats` suite runs entirely offline against fixture JSON files.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

MIT
