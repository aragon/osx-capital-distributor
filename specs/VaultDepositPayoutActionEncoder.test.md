# VaultDepositPayoutActionEncoder Test Plan

## Overview

The `VaultDepositPayoutActionEncoder` is a critical component that encodes payout actions for depositing tokens into campaign-specific vaults. Currently, this contract has **minimal test coverage** (only 1 superficial integration test), making it a high-priority testing gap.

### Current State
- **Contract**: `src/payoutActionEncoders/VaultDepositPayoutActionEncoder.sol`
- **Test Coverage**: ~5% (1 integration test that only checks deployment)
- **Risk Level**: HIGH - Handles token approvals and vault interactions

### Testing Goals
1. Test all public functions thoroughly
2. Verify error conditions and access control
3. Test action building logic with various parameters
4. Ensure vault configuration works correctly
5. Test integration with factories and plugin

## Contract Analysis

### Key Functions

1. **`setupCampaign`**
   - Sets vault address for a specific campaign
   - Access controlled (DAO or owner only)
   - Validates vault address is not zero
   - Emits CampaignVaultSet event

2. **`buildActions`**
   - Creates two actions: approve and deposit
   - Validates amount is not zero
   - Validates vault is configured for campaign
   - Returns array of executable actions

3. **`getCreationEncodingTypes`**
   - Returns "address" for vault address encoding
   - Pure function

4. **`getClaimEncodingTypes`**
   - Returns empty string (no claim-time encoding needed)
   - Pure function

### Key State
- `campaignVaults`: Maps campaignId to vault address
- Inherits from PayoutActionEncoderBase (DaoAuthorizableUpgradeable)

## Test Strategy

### Approach
1. Follow pattern from other encoder tests (e.g., SablierLinearPayoutActionEncoder)
2. Test each function with valid and invalid inputs
3. Test access control thoroughly
4. Mock vault contract for interaction tests
5. Test full integration with factory deployment

### Test File Location
`tests/VaultDepositPayoutActionEncoderTest.t.sol`

## Detailed Test Cases

### 1. Initialization & Setup Tests (5 tests)

#### test_Initialization_Success
**Description**: Verify encoder initializes correctly when deployed by factory
**Setup**:
- Deploy encoder via factory
- Create mock DAO
**Actions**:
- Deploy encoder with valid auxData
- Query initialization state
**Assertions**:
- `dao()` returns correct DAO address
- `encoderId()` returns correct ID
- `owner()` returns correct deployer

#### test_SetupCampaign_Success
**Description**: Test successful vault configuration for a campaign
**Setup**:
- Deploy encoder
- Create valid vault address
**Actions**:
- Call setupCampaign as DAO
- Pass valid vault address
**Assertions**:
- `campaignVaults[campaignId]` returns correct vault
- CampaignVaultSet event emitted with correct parameters

#### test_SetupCampaign_RevertNotDAO
**Description**: Ensure only DAO/owner can setup campaigns
**Setup**:
- Deploy encoder
- Use non-DAO address
**Actions**:
- Call setupCampaign as random address
**Assertions**:
- Reverts with `OnlyDAO(caller)` error

#### test_SetupCampaign_RevertZeroVault
**Description**: Ensure zero address vault is rejected
**Setup**:
- Deploy encoder as DAO
**Actions**:
- Call setupCampaign with address(0)
**Assertions**:
- Reverts with `ZeroAddressNotAllowed()` error

#### test_SetupCampaign_OwnerCanSetup
**Description**: Verify owner (deployer) can also setup campaigns
**Setup**:
- Deploy encoder
- Record owner address
**Actions**:
- Call setupCampaign as owner
**Assertions**:
- Setup succeeds
- Vault is configured correctly

### 2. Action Building Tests (8 tests)

#### test_BuildActions_Success
**Description**: Test successful action building with valid parameters
**Setup**:
- Configure vault for campaign
- Create mock token
**Actions**:
- Call buildActions with valid parameters
**Assertions**:
- Returns array of length 2
- First action is token approval
- Second action is vault deposit
- Action parameters are correct

#### test_BuildActions_CorrectApprovalAction
**Description**: Verify approval action structure
**Setup**:
- Configure vault for campaign
**Actions**:
- Build actions
- Decode first action
**Assertions**:
```solidity
assertEq(actions[0].to, address(token));
assertEq(actions[0].value, 0);
// Decode and verify it's approve(vault, amount)
(address spender, uint256 approveAmount) = abi.decode(
    actions[0].data[4:], 
    (address, uint256)
);
assertEq(spender, vaultAddress);
assertEq(approveAmount, amount);
```

#### test_BuildActions_CorrectDepositAction
**Description**: Verify deposit action structure
**Setup**:
- Configure vault for campaign
**Actions**:
- Build actions
- Decode second action
**Assertions**:
```solidity
assertEq(actions[1].to, vaultAddress);
assertEq(actions[1].value, 0);
// Decode and verify it's deposit(amount, recipient)
(uint256 depositAmount, address depositRecipient) = abi.decode(
    actions[1].data[4:],
    (uint256, address)
);
assertEq(depositAmount, amount);
assertEq(depositRecipient, recipient);
```

#### test_BuildActions_RevertZeroAmount
**Description**: Ensure zero amount is rejected
**Setup**:
- Configure vault for campaign
**Actions**:
- Call buildActions with amount = 0
**Assertions**:
- Reverts with `AmountCannotBeZero()` error

#### test_BuildActions_RevertNoVault
**Description**: Ensure missing vault configuration is caught
**Setup**:
- Deploy encoder (no vault setup)
**Actions**:
- Call buildActions for unconfigured campaign
**Assertions**:
- Reverts with `VaultNotSetForCampaign(campaignId)` error

#### test_BuildActions_DifferentCampaigns
**Description**: Test multiple campaigns with different vaults
**Setup**:
- Configure vault1 for campaign1
- Configure vault2 for campaign2
**Actions**:
- Build actions for both campaigns
**Assertions**:
- Each uses correct vault address
- Actions are independent

#### test_BuildActions_SameVaultMultipleCampaigns
**Description**: Test same vault for multiple campaigns
**Setup**:
- Configure same vault for multiple campaigns
**Actions**:
- Build actions for each campaign
**Assertions**:
- All use same vault address correctly

#### testFuzz_BuildActions_Amounts
**Description**: Fuzz test various amounts
**Setup**:
- Configure vault
- Fuzz amount (non-zero)
**Actions**:
- Build actions with fuzzed amount
**Assertions**:
- Approval and deposit use correct amount

### 3. Encoding Tests (4 tests)

#### test_GetCreationEncodingTypes
**Description**: Verify creation encoding types
**Actions**:
- Call getCreationEncodingTypes
**Assertions**:
- Returns "address"

#### test_GetClaimEncodingTypes
**Description**: Verify claim encoding types
**Actions**:
- Call getClaimEncodingTypes
**Assertions**:
- Returns "" (empty string)

#### test_CreationAuxDataDecoding
**Description**: Test auxData decoding in setupCampaign
**Setup**:
- Encode a vault address
**Actions**:
- Pass encoded data to setupCampaign
**Assertions**:
- Vault is set correctly
- No decoding errors

#### test_InvalidAuxDataLength
**Description**: Test malformed auxData handling
**Setup**:
- Create invalid auxData (wrong length)
**Actions**:
- Try to setup campaign
**Assertions**:
- Appropriate revert (abi decoding error)

### 4. Integration Tests (3 tests)

#### test_FactoryIntegration_FullFlow
**Description**: Test complete flow from factory deployment
**Setup**:
- Deploy and register encoder in factory
- Deploy plugin and create campaign
**Actions**:
- Deploy encoder via factory
- Setup vault for campaign
- Build and execute actions
**Assertions**:
- Encoder deploys correctly
- Vault configuration works
- Actions execute successfully

#### test_Integration_WithMockVault
**Description**: Test with a mock vault implementation
**Setup**:
- Create MockVault with deposit tracking
- Configure encoder
**Actions**:
- Build actions
- Execute actions (simulate)
**Assertions**:
- Vault receives correct deposit call
- Parameters match expected

#### test_Integration_MultipleEncoders
**Description**: Test multiple encoder instances
**Setup**:
- Deploy multiple encoders for different DAOs
**Actions**:
- Configure each independently
- Build actions for each
**Assertions**:
- Encoders are isolated
- No cross-contamination

### 5. Edge Cases & Security Tests (3 tests)

#### test_ReentrancyProtection
**Description**: Ensure no reentrancy in setupCampaign
**Setup**:
- Create malicious vault contract
**Actions**:
- Attempt reentrancy during setup
**Assertions**:
- Reentrancy is prevented

#### test_LargeAmounts
**Description**: Test with maximum uint256 values
**Setup**:
- Configure vault
**Actions**:
- Build actions with type(uint256).max
**Assertions**:
- No overflow
- Actions built correctly

#### test_GasOptimization
**Description**: Ensure reasonable gas usage
**Setup**:
- Standard configuration
**Actions**:
- Measure gas for buildActions
**Assertions**:
- Gas usage is reasonable (<100k)

## Mock Contracts

### MockVault
```solidity
contract MockVault is IVault {
    mapping(address => uint256) public deposits;
    
    event DepositMade(uint256 amount, address recipient);
    
    function deposit(uint256 _amount, address _recipient) external override {
        deposits[_recipient] += _amount;
        emit DepositMade(_amount, _recipient);
    }
}
```

### MockToken
```solidity
contract MockToken is ERC20 {
    mapping(address => mapping(address => uint256)) public allowances;
    
    function approve(address spender, uint256 amount) public override returns (bool) {
        allowances[msg.sender][spender] = amount;
        return true;
    }
}
```

## Test Helpers

```solidity
function deployEncoder(address dao) internal returns (VaultDepositPayoutActionEncoder) {
    // Deploy via factory pattern
}

function setupVault(
    VaultDepositPayoutActionEncoder encoder,
    uint256 campaignId,
    address vault
) internal {
    vm.prank(address(dao));
    encoder.setupCampaign(campaignId, abi.encode(vault));
}

function verifyApprovalAction(
    Action memory action,
    address token,
    address spender,
    uint256 amount
) internal {
    assertEq(action.to, token);
    assertEq(action.value, 0);
    bytes4 selector = bytes4(action.data);
    assertEq(selector, IERC20.approve.selector);
    // Decode and verify parameters
}
```

## Open Questions

1. **Vault Interface**: The IVault interface is defined inline. Should this be moved to interfaces directory?

2. **Permission Checks**: The SET_VAULT_PERMISSION_ID is defined but not used. Should setupCampaign check this permission instead of just DAO/owner?

3. **Claim Data**: The encoder doesn't use claim-time auxData. Is this intentional or should we plan for future use?

4. **Error Handling**: Should the encoder validate that the vault address has code (is a contract)?

5. **Action Ordering**: Is the order (approve then deposit) critical? Should we test reverse order fails?

## Implementation Notes

1. **Base Contract**: Remember to test inherited functionality from PayoutActionEncoderBase

2. **Access Control**: The contract uses both DAO check and owner check - ensure both paths are tested

3. **Event Testing**: Always verify event emission for setupCampaign

4. **Factory Pattern**: Follow the factory deployment pattern used by other encoders

## Total Tests: ~23 tests

This comprehensive test suite will bring the VaultDepositPayoutActionEncoder from minimal coverage to full coverage, ensuring all functionality is properly tested.