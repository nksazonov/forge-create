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
forge-create src/MyContract.sol:MyContract --rpc-url <your-rpc-url> --private-key <your-private-key>
```

Additional options specific to `forge-create`:

```txt
--no-save          Don't save output to JSON file
--save-out PATH    Path where to save the JSON files (default: ./deployments)
--comment "TEXT"   Add a comment to the stored JSON file
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

## File Structure

Deployment files are organized by chain ID and contract name:

```bash
deployments/
├── 1/                        # Ethereum Mainnet (Chain ID: 1)
│   └── MyContract.sol:MyContract/
│       └── 2025-05-21T12:00:00.json
├── 5/                        # Goerli Testnet (Chain ID: 5)
│   └── MyContract.sol:MyContract/
│       ├── 2025-05-22T15:30:42.json
│       └── 2025-05-22T15:30:42-1.json  # Counter added for same-second deploys
└── 31337/                    # Local Anvil Chain (Chain ID: 31337)
    └── MyContract.sol:MyContract/
        └── 2025-05-23T10:15:00.json
```

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

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

MIT
