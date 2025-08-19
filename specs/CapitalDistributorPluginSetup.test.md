# CapitalDistributorPluginSetup Test Plan

## Overview

The `CapitalDistributorPluginSetup` contract is responsible for installing, uninstalling, and updating the CapitalDistributorPlugin in Aragon OSx DAOs. Currently, this critical contract has **ZERO test coverage**, making it a high-priority testing gap.

### Current State
- **Contract**: `src/CapitalDistributorPluginSetup.sol`
- **Test Coverage**: 0% (No dedicated test file exists)
- **Risk Level**: HIGH - Setup contracts handle critical permissions and initialization

### Testing Goals
1. Achieve 100% function coverage
2. Test all error conditions and reverts
3. Verify permission management correctness
4. Ensure proxy deployment works as expected
5. Validate the full installation/uninstallation lifecycle

## Contract Analysis

### Key Functions

1. **`prepareInstallation`**
   - Deploys plugin proxy via UUPS pattern
   - Initializes plugin with factories
   - Returns 3 permissions to be granted
   - Validates factory addresses are not zero

2. **`prepareUninstallation`**
   - Validates helper array length (must be 1)
   - Returns 3 permissions to be revoked
   - Reverses all installation permissions

3. **`prepareUpdate`**
   - Currently empty implementation
   - Returns empty data structures

4. **`decodeInstallationParams`**
   - Pure function to decode installation parameters
   - Extracts strategy and encoder factory addresses

### Permission Structure

The setup manages three critical permissions:

1. **UPGRADE_PLUGIN_PERMISSION_ID**
   - Where: Plugin
   - Who: DAO
   - Purpose: Allows DAO to upgrade plugin implementation

2. **EXECUTE_PERMISSION_ID**
   - Where: DAO
   - Who: Plugin
   - Purpose: Allows plugin to execute actions on DAO

3. **CAMPAIGN_CREATOR_PERMISSION_ID**
   - Where: Plugin
   - Who: DAO
   - Purpose: Allows DAO to create campaigns

## Test Strategy

### Approach
1. Test each function in isolation
2. Test the complete installation/uninstallation flow
3. Verify all error conditions
4. Use mock contracts where appropriate
5. Follow existing test patterns from other setup contracts

### Test File Location
`tests/CapitalDistributorPluginSetupTest.t.sol`

## Detailed Test Cases
CapitalDistributorPluginSetupTest:
  - when: deploying a new instance
    then:
      - it: completes without errors
  - when: preparing an installation
    and:
      - when: passing an invalid token contract
        then:
          - it: should revert
      - it: should return the plugin address
      - it: should return a list with the helpers (if any)
      - it: all plugins use the same implementation
      - it: the plugin has the given settings
      - it: should set the address of the factories on the plugin
      - it: the plugin should have the right factories address
      - it: the list of permissions should match
  - when: preparing an uninstallation
    and:
      - given: a list of helpers
        then:
          - it: should revert
      - it: generates a correct list of permission changes

## Mock Requirements

### MockDAO
```solidity
contract MockDAO is IDAO {
    mapping(address => mapping(address => mapping(bytes32 => bool))) permissions;

    function hasPermission(
        address _where,
        address _who,
        bytes32 _permissionId,
        bytes _data
    ) external view returns (bool) {
        return permissions[_where][_who][_permissionId];
    }

    function grant(address _where, address _who, bytes32 _permissionId) external {
        permissions[_where][_who][_permissionId] = true;
    }
}
```

### Test Helpers
```solidity
function encodeInstallationParams(
    address _strategyFactory,
    address _encoderFactory
) internal pure returns (bytes memory) {
    return abi.encode(_strategyFactory, _encoderFactory);
}

function applyPermissions(
    MockDAO dao,
    PermissionLib.MultiTargetPermission[] memory permissions
) internal {
    for (uint i = 0; i < permissions.length; i++) {
        if (permissions[i].operation == PermissionLib.Operation.Grant) {
            dao.grant(
                permissions[i].where,
                permissions[i].who,
                permissions[i].permissionId
            );
        }
    }
}
```

## Open Questions for Feedback

1. **Helper Array Purpose**: The contract expects exactly 1 helper during uninstallation but returns 0 helpers during installation. What is the intended helper? Should we modify the logic?

2. **Update Function**: The `prepareUpdate` function is empty. Is this intentional? Should we test for specific revert conditions or just verify it returns empty?

3. **Integration Testing Depth**: How deep should integration tests go? Should we test with real PluginSetupProcessor or just mock the permission application?

4. **Factory Validation**: Should the setup contract validate that provided addresses actually implement the expected factory interfaces?

5. **Permission Conditions**: All permissions use `NO_CONDITION`. Should we test with conditional permissions in the future?

## Implementation Notes

1. **Import Requirements**:
   - Import PluginUpgradeableSetup base contract
   - Import PermissionLib for permission structures
   - Import ProxyLib for deployment verification

2. **Test Structure**:
   - Inherit from AragonTest or create minimal test base
   - Set up factories in setUp() function
   - Use clear, descriptive test names

3. **Gas Considerations**:
   - Monitor gas usage for installation
   - Ensure reasonable limits

4. **Event Testing**:
   - The base contract likely emits events
   - Test for proper event emission

## Example Test Structure

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {CapitalDistributorPluginSetup} from "../src/CapitalDistributorPluginSetup.sol";
import {AllocatorStrategyFactory} from "../src/factories/AllocatorStrategyFactory.sol";
import {ActionEncoderFactory} from "../src/factories/ActionEncoderFactory.sol";
// ... other imports

contract CapitalDistributorPluginSetupTest is Test {
    CapitalDistributorPluginSetup setup;
    AllocatorStrategyFactory strategyFactory;
    ActionEncoderFactory encoderFactory;
    MockDAO dao;

    function setUp() public {
        setup = new CapitalDistributorPluginSetup();
        strategyFactory = new AllocatorStrategyFactory();
        encoderFactory = new ActionEncoderFactory();
        dao = new MockDAO();
    }

    function test_PrepareInstallation_Success() public {
        // Test implementation here
    }

    // ... other tests
}
```

## Next Steps

1. Review this test plan and provide feedback on open questions
2. Provide any specific examples or patterns you'd like followed
3. Clarify any business logic questions
4. Approve the test structure and approach

Once feedback is incorporated, we can proceed with implementing these 19 comprehensive tests to achieve full coverage of the CapitalDistributorPluginSetup contract.
