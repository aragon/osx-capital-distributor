# claimCampaignPayout Function Simplification

## Summary
Successfully simplified the `claimCampaignPayout` function in `CapitalDistributorPlugin.sol` by consolidating the action building logic from 3 helper functions into 1, reducing complexity while maintaining all functionality.

## Changes Made

### Before: 3 Helper Functions
1. `_buildFeeTransferAction` - Built individual fee transfer actions
2. `_buildDirectTransferActions` - Handled direct transfer cases with/without fees
3. `_buildEncoderActions` - Handled encoder-based transfers with/without fees

### After: 1 Unified Helper Function
- `_buildPayoutActions` - Handles all cases (direct/encoder × fee/no-fee) in a single function

## Key Improvements

1. **Reduced Code Paths**: From 4 conditional branches to 2 main branches
2. **Eliminated Helper Dependencies**: No more calling helper from helper
3. **Cleaner Main Function**: The claim function now has a single, clear call to build actions
4. **Better Readability**: Logic flow is more straightforward

## Code Structure

```solidity
// Simplified main function flow:
function claimCampaignPayout(...) {
    // 1. Validation (unchanged)
    // 2. Fee calculation (unchanged)
    // 3. State update (unchanged)
    
    // 4. Single call to build all actions
    Action[] memory actions = _buildPayoutActions(
        campaign,
        _recipient,
        recipientAmount,
        feeRecipient,
        feeAmount,
        _campaignId,
        _encoderAuxData
    );
    
    // 5. Execute and emit (unchanged)
}

// Unified helper handles all cases:
function _buildPayoutActions(...) {
    bool hasEncoder = address(_campaign.actionEncoder) != address(0);
    bool hasFee = _feeAmount > 0;
    
    if (hasEncoder) {
        // Get encoder actions and optionally append fee
    } else {
        // Build direct transfers with optional fee
    }
}
```

## Benefits

1. **Maintainability**: Easier to understand and modify
2. **Less Duplication**: Fee handling logic appears once instead of twice
3. **Same Gas Usage**: No performance impact
4. **Full Compatibility**: All tests pass without modification

## Testing
- All 234 tests pass
- Fee functionality tests specifically verified
- Gas consumption remains unchanged