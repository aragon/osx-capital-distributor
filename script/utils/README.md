# Merkle Tree Tools

Solidity-based merkle tree utilities for OSX Capital Distributor using Foundry.

## Scripts

### Create Example Recipients

```bash
forge script scripts/merkleDistributor/CreateExampleRecipients.s.sol:CreateExampleRecipients \
  --sig "createExample(string)" "recipients.json" --via-ir
```

### Generate Merkle Tree

```bash
forge script scripts/merkleDistributor/GenerateMerkleTree.s.sol:GenerateMerkleTree \
  --sig "generate(string)" "recipients.json" --via-ir
```

### Generate Proof

```bash
forge script scripts/merkleDistributor/GenerateProof.s.sol:GenerateProof \
  --sig "generateProof(string,address)" "merkle-tree.json" "0x123..." --via-ir
```

### Verify Proof

```bash
forge script scripts/merkleDistributor/VerifyProof.s.sol:VerifyProof \
  --sig "verifyFromFile(string)" "proof-0x123....json" --via-ir
```

## File Format

**recipients.json:**

```json
[
  { "account": "0x123...", "amount": "1000000000000000000" },
  { "account": "0x456...", "amount": "2000000000000000000" }
]
```

## Requirements

- Add to `foundry.toml`: `fs_permissions = [{ access = "read-write", path = "./" }]`
- Always use `--via-ir` flag
- Amounts in wei as strings
- Valid Ethereum addresses with 0x prefix
- No duplicate addresses

## Integration

Generated proofs work directly with `MerkleDistributorStrategy`:

```solidity
// Use merkleRoot from merkle-tree.json
bytes memory allocationData = abi.encode(merkleRoot);

// Use proof from proof-{address}.json
bytes memory claimData = abi.encode(merkleProof, amount);
```
