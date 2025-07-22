# Test Data Files

This directory contains sample JSON files for testing the merkle tree utilities.

## Files

### Valid Test Data
- `sample-recipients.json` - Basic example with 4 recipients and various amounts
- `testnet-recipients.json` - Recipients using well-known testnet addresses (Anvil/Hardhat)

### Invalid Test Data
- `invalid-recipients.json` - Contains validation errors for testing error handling

## File Format

Recipients JSON files should follow this format:

```json
[
  {
    "account": "0x1234567890123456789012345678901234567890",
    "amount": "1000000000000000000"
  }
]
```

### Field Requirements
- `account`: Valid Ethereum address (40 hex characters with 0x prefix)
- `amount`: Amount in wei as a string (to handle large numbers)

### Common Validation Errors
- Invalid address format
- Zero or negative amounts
- Duplicate addresses
- Missing required fields

## Usage with Scripts

These files can be used with the merkle tree generation scripts:

```bash
# Generate merkle tree
forge script scripts/merkleDistributor/GenerateMerkleTree.s.sol:GenerateMerkleTree \
  --sig "generate(string)" "test/scripts/data/sample-recipients.json"

# Create example file
forge script scripts/merkleDistributor/CreateExampleRecipients.s.sol:CreateExampleRecipients \
  --sig "createExample(string)" "my-recipients.json"
```