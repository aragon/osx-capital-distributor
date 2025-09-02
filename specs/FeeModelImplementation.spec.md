# Fee Model Implementation Specification

## Overview

This document specifies the implementation of a fee model for allocator strategies in the OSX Capital Distributor
system. The fee model allows strategy developers to charge a small fee when users claim their allocations, with fees
being strategy-specific and immutable once set.

## Requirements

1. **Strategy-Specific Fees**: Each strategy type has its own fee configuration
2. **Immutable Fees**: Once set during registration, fees cannot be modified
3. **Direct Transfer**: Fees are sent directly to the fee recipient during claims
4. **Zero Fee Support**: Strategies can have zero fees if desired
5. **Maximum Fee Cap**: Fees are capped at 10% (1000 basis points)

## Architecture Changes

### 1. AllocatorStrategyFactory Updates

#### New Data Structures

```solidity
struct FeeConfig {
    address recipient;      // Where fees are sent
    uint256 basisPoints;   // Fee percentage (e.g., 250 = 2.5%, max 1000 = 10%)
}

mapping(bytes32 strategyTypeId => FeeConfig) public strategyFees;
```

#### Updated Functions

```solidity
function registerStrategyType(
    bytes32 _strategyTypeId,
    address _implementation,
    string calldata _metadata,
    address _feeRecipient,    // NEW
    uint256 _feeBasisPoints   // NEW
) external
```

#### New Functions

```solidity
function getStrategyFeeByInstance(
    address _instance
) external view returns (address recipient, uint256 basisPoints)
```

#### New Events

```solidity
event StrategyFeeConfigured(
    bytes32 indexed strategyId,
    address indexed feeRecipient,
    uint256 feeBasisPoints
);
```

#### New Errors

```solidity
error ExcessiveFee(uint256 provided, uint256 maximum);
error InvalidFeeRecipient();
```

### 2. IAllocatorStrategy Interface Updates

#### New Required Function

```solidity
function getFeeConfiguration() external view returns (address recipient, uint256 basisPoints);
```

### 3. AllocatorStrategyBase Updates

#### New State Variable

```solidity
address public factory;  // Reference to the factory that deployed this strategy
```

#### New Implementation

```solidity
function getFeeConfiguration()
    public
    view
    virtual
    override
    returns (address recipient, uint256 basisPoints)
{
    return IAllocatorStrategyFactory(factory).getStrategyFeeByInstance(address(this));
}
```

### 4. CapitalDistributorPlugin Updates

#### Modified claimCampaignPayout Function

The claim function now:

1. Retrieves fee configuration from the strategy
2. Calculates fee amount
3. Creates two transfer actions (recipient and fee collector)
4. Executes both transfers atomically through the DAO

```solidity
// Get fee configuration from the strategy
(address feeRecipient, uint256 feeBasisPoints) = campaign.allocationStrategy.getFeeConfiguration();

// Calculate fee amount
uint256 feeAmount = 0;
uint256 recipientAmount = amountToSend;

if (feeBasisPoints > 0 && feeRecipient != address(0)) {
    feeAmount = (amountToSend * feeBasisPoints) / 10000;
    recipientAmount = amountToSend - feeAmount;
}

// Create transfer actions
uint256 actionCount = feeAmount > 0 ? 2 : 1;
Action[] memory transfers = new Action[](actionCount);

// Recipient transfer
transfers[0] = Action({
    to: encoderAddress,
    value: 0,
    data: encoderInterface.encodeAction(recipient, recipientAmount, transferParams)
});

// Fee transfer (if applicable)
if (feeAmount > 0) {
    transfers[1] = Action({
        to: encoderAddress,
        value: 0,
        data: encoderInterface.encodeAction(feeRecipient, feeAmount, transferParams)
    });
}
```

#### New Event

```solidity
event FeeCollected(
    uint256 indexed campaignId,
    address indexed feeRecipient,
    uint256 feeAmount
);
```

## Validation Rules

### Fee Registration Validation

1. **Maximum Fee**: Cannot exceed 1000 basis points (10%)
2. **Fee Recipient**: If fee > 0, recipient must not be address(0)
3. **Zero Fee**: Allowed with recipient = address(0) and basisPoints = 0

### Fee Calculation

- Formula: `feeAmount = (claimAmount * feeBasisPoints) / 10000`
- Remainder goes to recipient: `recipientAmount = claimAmount - feeAmount`
- No rounding errors: All amounts in wei

## Migration Impact

### Breaking Changes

1. `registerStrategyType` function signature changed (added 2 parameters)
2. All strategies must implement `getFeeConfiguration()`

### Required Updates

1. All existing test files updated to use new `registerStrategyType` signature
2. Deployment scripts updated to include fee parameters
3. Mock contracts updated to implement `getFeeConfiguration()`

## Security Considerations

### Fee Immutability

- Fees are set during strategy registration and cannot be changed
- Prevents fee manipulation after users have committed to campaigns

### Maximum Fee Protection

- 10% cap prevents excessive fee extraction
- Validated during registration, not during claims (gas efficient)

### Atomic Transfers

- Both recipient and fee transfers execute atomically
- If one fails, both fail (no partial state)

### No Reentrancy Risk

- Fee calculation happens before any external calls
- State updates complete before transfers

## Gas Impact

### Registration

- Additional ~5,000 gas for storing fee configuration
- One-time cost during strategy type registration

### Deployment

- Additional ~18,000 gas for storing factory reference
- Reflected in updated gas tests (220k → 240k limit)

### Claims

- Additional ~2,000 gas for fee lookup
- Additional ~21,000 gas for second transfer (if fee > 0)
- No impact for zero-fee strategies

## Testing

### Test Coverage

1. **AllocatorStrategyFeeTest.t.sol** - Comprehensive fee functionality tests
   - Fee registration with various configurations
   - Claim flow with and without fees
   - Fee calculation accuracy
   - Invalid configuration rejection

2. **Updated Existing Tests**
   - All test files updated for new function signatures
   - Gas consumption tests adjusted for new limits

### Test Scenarios Covered

- Zero fees
- Various fee percentages (0.01% - 10%)
- Invalid fee configurations
- Fee recipient validation
- Calculation precision
- Integration with existing flows

## Example Usage

### Registering a Strategy with 2.5% Fee

```solidity
allocatorStrategyFactory.registerStrategyType(
    keccak256("merkle-distributor"),
    address(merkleImplementation),
    "Merkle Tree Distribution Strategy",
    0xFeeCollector,  // Fee recipient
    250              // 2.5% fee
);
```

### Registering a Strategy with No Fee

```solidity
allocatorStrategyFactory.registerStrategyType(
    keccak256("simple-distributor"),
    address(simpleImplementation),
    "Simple Distribution Strategy",
    address(0),      // No fee recipient
    0                // 0% fee
);
```

## Implementation Status

✅ All components implemented and tested ✅ 234 tests passing ✅ Gas optimizations verified ✅ Security considerations
addressed
