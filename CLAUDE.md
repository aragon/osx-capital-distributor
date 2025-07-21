# CLAUDE.md - Smart Contract Development Guide

## Core Rules
1. **NEVER proceed without explicit approval** - Always stop and wait after planning
2. **Every change must be documented** - No exceptions
3. **Security first** - Think like an attacker, code like a defender
4. **Small changes only** - No massive refactors

## Environment Setup
```bash
# Build & Test
forge build --via-ir
forge test --via-ir -vvv
forge coverage --via-ir

# Gas Analysis
forge test --gas-report --via-ir
forge snapshot --via-ir  # Creates .gas-snapshot for tracking

# Security Analysis
slither . --exclude naming-convention,external-function
```

## Code Standards
```solidity
// ✅ Use destructured imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ✅ Use custom errors (saves gas)
error TransferToZeroAddress();
error InsufficientBalance(uint256 available, uint256 required);

// ✅ Full NatSpec for EVERYTHING
/**
 * @notice Transfer tokens to a user
 * @param to Recipient address
 * @param amount Amount in wei
 * @custom:security-note Checks for zero address
 */
function transfer(address to, uint256 amount) external returns (bool) {
    if (to == address(0)) revert TransferToZeroAddress();
    if (balances[msg.sender] < amount) {
        revert InsufficientBalance(balances[msg.sender], amount);
    }
    // ...
}
```

### Code Cleanliness Rules
- **No magic numbers** - Use named constants: `uint256 constant BASIS_POINTS = 10_000;`
- **Explicit over clever** - Readable code > gas micro-optimizations
- **Single responsibility** - Each function does ONE thing
- **Early returns** - Fail fast with requires/reverts at the top
- **Consistent ordering** - Events, Errors, Modifiers, Constructor, External, Public, Internal, Private
- **No dead code** - If it's not used, delete it
- **Clear naming** - `withdrawUserFunds()` not `wuf()` or `withdraw()`

## Development Workflow

### 1. Requirements Analysis (NEW - MUST DO FIRST)

Before ANY coding, create `tasks/{task-name}-requirements.md`:
```markdown
# Requirements Analysis: {Task Name}

## Requested Features
- [ ] Feature A - NEEDED? [Yes/No - Why]
- [ ] Feature B - NEEDED? [Yes/No - Why]

## Minimal Implementation
What's the absolute minimum to solve the problem?
- Core function X (required for Y)
- Access control (required for security)
- Events (required for monitoring)

## Explicitly NOT Adding
- Feature Z (not in requirements)
- Extra getters (frontend can calculate)
- Convenience functions (can add later if needed)

## Final Scope
Only implementing:
1. Function X with validation Y
2. Event Z for monitoring
```

**Get approval on requirements BEFORE proceeding**

### 2. Planning Phase (STOP HERE FOR APPROVAL)

Create these files before coding:

**Contract Spec** - `specs/contracts/{ContractName}.spec.md`:
```markdown
# Contract: {ContractName}

## Purpose
[What this contract does]

## Functions

### transfer(address to, uint256 amount) → bool
- **Access**: Public
- **Description**: Transfers tokens from msg.sender to recipient
- **Validations**:
  - to != address(0)
  - amount <= balance[msg.sender]
- **Events**: Transfer(from, to, amount)
- **Security**: No reentrancy risk

### pause() → void
- **Access**: onlyOwner
- **Description**: Pauses all transfers
- **Events**: Paused(account)

## State Variables
- `mapping(address => uint256) public balances`
- `bool public paused`

## Invariants
- Sum of all balances == totalSupply
- No balance > totalSupply
```

**Task Plan** - `tasks/{task-name}.md`:
```markdown
# Task: {Task Name}

## Goal
[What we're building]

## Steps
- [ ] Implement function X
- [ ] Add tests for edge cases
- [ ] Security validation

## Security Risks
- Reentrancy on function Y
- Access control on function Z
```

### 2. Implementation Phase

**Before ANY code change:**
1. Explain what you're about to change
2. Show the exact code modification
3. **WAIT FOR APPROVAL**

**After EACH change:**
1. Run `forge build --via-ir`
2. Run relevant tests
3. Update the change report

**Change Report** - `reports/changes/{timestamp}-{feature}.md`:
```markdown
# Change: {Feature Name}
Date: {timestamp}

## What Changed
- `Contract.sol`: Added transfer function with zero-address check

## Security Review
- **Slither**: No high/medium issues
- **New Risks**: None identified
- **Tests Added**: testTransferZeroAddress

## Spec Sync
- [ ] Updated Contract.spec.md to match implementation
```

### 3. Validation

After every change, run:
```bash
forge test --via-ir
slither .
```

## Contract Spec Sync Rules

**IMPORTANT**: If spec and contract don't match, **STOP AND ASK**:
- "The spec shows function X but the contract doesn't have it. Should I implement it or update the spec?"
- "The contract has function Y but it's not in the spec. Should I remove it or update the spec?"

Check sync by comparing:
1. All functions in spec exist in contract
2. All contract functions are documented in spec
3. Access controls match
4. Parameters and return types match

## Security Checklist

For EVERY function:
- [ ] Input validation (no zero addresses, bounds checks)
- [ ] Access control (who can call this?)
- [ ] State changes before external calls
- [ ] Events emitted for all state changes
- [ ] No unbounded loops

## Extra Security Validations

Run these checks periodically, not just after changes:

### 1. Invariant Testing
```solidity
// Add invariant tests that run continuously
function invariant_balanceSum() public {
    uint256 sum;
    for(uint i; i < holders.length; i++) {
        sum += balances[holders[i]];
    }
    assertEq(sum, totalSupply);
}
```

### 2. Formal Property Checks
- **No token creation** - totalSupply only changes via mint/burn
- **No value extraction** - Contract balance >= sum of user deposits
- **Monotonic nonces** - Nonces only increase, never decrease
- **Time consistency** - No action can happen before block.timestamp

### 3. Economic Security
- **Frontrunning analysis** - Can MEV bots exploit this?
- **Griefing vectors** - Can someone DOS the contract cheaply?
- **Economic incentives** - Are incentives aligned correctly?

### 4. Integration Risks
- **Composability** - How does this interact with other contracts?
- **Upgrade safety** - If upgradeable, storage layout preserved?
- **Oracle dependencies** - What happens if oracle fails?

## Quick Reference

### Common Patterns
```solidity
// Checks-Effects-Interactions
require(condition);          // Check
state = newValue;           // Effect
external.call();            // Interaction

// Always use
nonReentrant
onlyOwner/AccessControl
SafeERC20 for token transfers
```

### Emergency Response
If you find a critical vulnerability:
1. **STOP**
2. Create `reports/CRITICAL-{timestamp}.md`
3. **DO NOT FIX** without approval

## File Structure
```
/
├── contracts/          # Smart contracts
├── specs/
│   └── contracts/     # Contract specifications (MUST match implementation)
├── tasks/             # Task plans
├── reports/
│   └── changes/       # Change documentation with security review
└── docs/
    └── security/      # Threat models and security architecture
```

Remember: **Every contract must have a matching spec file that stays in sync**
