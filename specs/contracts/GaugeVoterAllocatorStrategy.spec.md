# Contract: GaugeVoterAllocatorStrategy

## Purpose

Allocator strategy that distributes tokens proportionally to users based on their voting participation and power in
Aragon OSx Gauge voting plugin. Users receive allocations based on how much voting power they contributed to the gauge
in the last voting round relative to the total voting power cast.

## Inheritance

- Extends: `AllocatorStrategyBase`
- Implements: `IAllocatorStrategy` (through base contract)

## State Variables

### Campaign Configuration

- `mapping(uint256 => GaugeAllocationCampaign) public campaigns` - Campaign-specific configuration
- `IAddressGaugeVoter public gaugeVoter` - Reference to the Aragon OSx Gauge voting plugin

### Data Structures

```solidity
struct GaugeAllocationCampaign {
    uint256 epochId;                 // Epoch ID when campaign was created
    uint256 totalDistributionAmount; // Total amount available for this campaign
}
```

## Functions

### initialize(bytes32 \_strategyTypeId, IDAO \_dao, address \_plugin, bytes calldata \_auxData) → void

- **Access**: External, initializer
- **Description**: Initializes the strategy with gauge voting plugin reference
- **Parameters**:
  - `_strategyTypeId`: Strategy type identifier
  - `_dao`: DAO instance
  - `_plugin`: Capital distributor plugin address
  - `_auxData`: Encoded (IAddressGaugeVoter gaugeVoter)
- **Validations**:
  - gaugeVoter != address(0)
- **Events**: None specific (inherits from base)

### setAllocationCampaign(uint256 \_campaignId, bytes calldata \_auxData) → void

- **Access**: External (only owner or DAO)
- **Description**: Configures a new allocation campaign for the current epoch. Can be created anytime, but claims only
  work during distribution periods
- **Parameters**:
  - `_campaignId`: Unique campaign identifier
  - `_auxData`: Encoded (uint256 totalDistributionAmount) - amount to distribute for this campaign
- **Validations**:
  - msg.sender is owner or DAO
  - Campaign doesn't already exist
  - totalDistributionAmount > 0
- **Effects**:
  - Creates new GaugeAllocationCampaign with current epochId
  - Stores totalDistributionAmount
  - Sets campaign as active
- **Events**: AllocationCampaignCreated(plugin, \_campaignId)
- **Note**: Campaign timing is managed by CapitalDistributorPlugin. Claims only work when campaign has started AND
  voting is inactive

### getClaimeableAmount(uint256 \_campaignId, address \_account, bytes calldata \_auxData) → uint256

- **Access**: External view
- **Description**: Calculates the claimeable amount for a user based on their gauge voting participation
- **Parameters**:
  - `_campaignId`: Campaign identifier
  - `_account`: User address to check allocation for
  - `_auxData`: Empty (not used for this strategy)
- **Returns**: Amount of tokens the account can claim
- **Logic**:
  1. Validate campaign exists
  2. Validate campaign epoch matches current epoch (gaugeVoter.epochId())
  3. Validate voting is not currently active (!gaugeVoter.votingActive())
  4. Get user's current voting power (gaugeVoter.usedVotingPower(\_account))
  5. Get total voting power cast (gaugeVoter.totalVotingPowerCast())
  6. Calculate proportional allocation: `(userVotingPower * totalDistributionAmount) / totalVotingPowerCast`
- **Validations**:
  - Campaign exists (epochId != 0)
  - Campaign epoch matches current epoch
  - Voting is not currently active (distribution period)
  - Total voting power > 0 (prevents division by zero)
- **Security**: No state changes, read-only function

### getInitializationEncodingTypes() → string

- **Access**: External pure
- **Description**: Returns encoding types for strategy initialization
- **Returns**: "address" (IAddressGaugeVoter)

### isUserEligible(uint256 \_campaignId, address \_account) → bool

- **Access**: Public view
- **Description**: Checks if user is eligible for allocation in the campaign
- **Parameters**:
  - `_campaignId`: Campaign identifier
  - `_account`: User address
- **Returns**: True if user is eligible
- **Logic**:
  1. Check campaign exists (epochId != 0)
  2. Check campaign epoch matches current epoch
  3. Check voting is not currently active
  4. Check user has voting power > 0

### getCreationEncodingTypes() → string

- **Access**: External pure
- **Description**: Returns encoding types for campaign creation
- **Returns**: "uint256" (totalDistributionAmount) for setAllocationCampaign

### getClaimEncodingTypes() → string

- **Access**: External pure
- **Description**: Returns encoding types for claim auxiliary data
- **Returns**: "" (empty - no auxiliary data needed for claiming)

### supportsInterface(bytes4 interfaceId) → bool

- **Access**: Public view virtual override
- **Description**: ERC165 interface support check
- **Returns**: True if interface is supported
- **Inherited**: From AllocatorStrategyBase

## Integration Requirements

### Gauge Voting Plugin Interface (IAddressGaugeVoter)

The strategy expects the gauge voting plugin to provide:

- `usedVotingPower(address _address) external view returns (uint256)` - gets user's current voting power
- `totalVotingPowerCast() external view returns (uint256)` - gets total voting power cast in current epoch
- `epochId() external view returns (uint256)` - gets current epoch ID
- `votingActive() external view returns (bool)` - checks if voting is currently active
- `epochStart() external view returns (uint256)` - timestamp of current epoch start
- `epochVoteStart() external view returns (uint256)` - timestamp of current voting period start
- `epochVoteEnd() external view returns (uint256)` - timestamp of current voting period end

## Security Considerations

### Access Control

- Only plugin owner or DAO can create campaigns
- All view functions are public for transparency
- No direct token handling (managed by CapitalDistributorPlugin)

### Validation Requirements

- Voting rounds must be completed before allocation
- Zero address checks on initialization
- Campaign existence validation
- Division by zero protection when calculating proportional amounts

### Economic Security

- Proportional distribution ensures fair allocation
- No double-spending (handled by plugin's claim tracking)
- Epoch validation prevents stale data usage

## Events

- Inherits `AllocationCampaignCreated` from IAllocatorStrategy

## Errors

```solidity
error CampaignNotFound(uint256 campaignId);
error EpochMismatch(uint256 campaignEpoch, uint256 currentEpoch);
error VotingCurrentlyActive();
error InvalidGaugeVoter();
error InvalidDistributionAmount();
```

## Usage Flow

1. Strategy is deployed and initialized with gauge voting plugin reference
2. DAO creates campaign through `setAllocationCampaign` with distribution amount (can be created anytime)
3. Campaign stores current epoch ID and distribution amount
4. Users can check their allocation with `getClaimeableAmount` (only works when campaign has started, in same epoch, and
   voting is inactive)
5. Users claim through the capital distributor plugin (not directly through strategy)
6. Plugin calls strategy to verify amounts during claim process

## Notes

- Strategy is read-only for users - all claiming is handled by CapitalDistributorPlugin
- Only works with current epoch data - no historical voting data available
- Campaigns can be created anytime, but claims only work during distribution periods (when voting is inactive)
- Claims only work in the same epoch as campaign creation and when campaign has started
- Strategy supports multiple concurrent campaigns within the same epoch
- Campaign amounts are provided during campaign creation, not fetched from plugin
- Campaign start timing is managed by CapitalDistributorPlugin, not the strategy

## Implementation Review Checklist

**Core Requirements (Must Have)**

- [x] Contract inherits from AllocatorStrategyBase correctly
- [x] IAddressGaugeVoter interface imported and used properly
- [x] GaugeAllocationCampaign struct has only: epochId, totalDistributionAmount (isActive removed)
- [x] State variables: campaigns mapping and gaugeVoter reference only

**Function Implementation (Must Have)**

- [x] initialize() takes IAddressGaugeVoter in \_auxData and validates != address(0)
- [x] setAllocationCampaign() can be called anytime and stores current epochId
- [x] setAllocationCampaign() takes only uint256 totalDistributionAmount in \_auxData
- [x] getClaimeableAmount() validates epoch match, voting inactive, and calculates proportionally
- [x] getInitializationEncodingTypes() returns "address" (IAddressGaugeVoter)
- [x] getCreationEncodingTypes() returns "uint256" only
- [x] getClaimEncodingTypes() returns empty string
- [x] isUserEligible() checks all validations and voting power > 0
- [x] Removed unused getUserVotingPower() and getTotalVotingPower() functions

**Validation Logic (Must Have)**

- [x] Campaign creation can happen anytime (no voting status check in setAllocationCampaign)
- [x] Claims only work when voting is inactive
- [x] Claims only work in same epoch as campaign creation
- [x] Proper division by zero protection in getClaimeableAmount()
- [x] Access control: only owner or DAO can create campaigns

**Error Handling (Must Have)**

- [x] All 5 custom errors defined: CampaignNotFound, EpochMismatch, VotingCurrentlyActive, InvalidGaugeVoter,
      InvalidDistributionAmount
- [x] Proper error throwing in all validation scenarios
- [x] Removed unused errors: CampaignNotActive, NoVotingPower

**Interface Usage (Must Have)**

- [x] Only uses gaugeVoter.usedVotingPower(address) for user voting power
- [x] Only uses gaugeVoter.totalVotingPowerCast() for total voting power
- [x] Only uses gaugeVoter.epochId() for current epoch
- [x] Only uses gaugeVoter.votingActive() for voting status check
- [x] No calls to non-existent interface methods

**Security & Best Practices (Must Have)**

- [x] No additional state variables beyond spec
- [x] No additional functions beyond spec
- [x] No token handling (handled by plugin)
- [x] No historical data access attempts
- [x] Proper NatSpec documentation on all functions

**What Should NOT Be There (Must Not Have)**

- [x] No minimum voting power requirements or validation
- [x] No direct interaction with CapitalDistributorPlugin for fetching amounts (distribution amount comes as parameter)
- [x] No attempt to access historical epoch data
- [x] No unused helper functions (getUserVotingPower, getTotalVotingPower removed)
- [x] No campaign deactivation functionality
- [x] No vote weight or gauge-specific calculations
- [x] No extra initialization parameters beyond IAddressGaugeVoter
- [x] No test files (implementation only)

**Edge Cases Handled (Must Have)**

- [x] Returns 0 when user has no voting power
- [x] Returns 0 when total voting power is 0
- [x] Handles campaign in wrong epoch gracefully
- [x] Handles voting active state correctly
- [x] Handles non-existent campaigns correctly (epochId == 0 check)

## Questions

- Can the campaign owner change some of the hardcoded values of the campaign (epochId, isActive,
  totalDistributionAmount)?
  - If so, how does this plugin react? I'm mostly worried about the distribution amount changing, not sure if can be
    done tho.
- Regarding aux data helpers for the frontend, it seems we may need three of them, and right now we only have two:
  - Initialization aux data
  - Campaign Creation aux data
  - Claiming aux data
  - Important: This would apply probably as well for the action encoders
- In the function setAllocationCampaing, I've left a message to you @claude. We should be calling the plugin back and
  request the amount, rather than passing it through a param than can be altered
- What is the isActive param used for?
- Left some comments in the `getClaimeableAmount()` function.
  - We should remove the campaign.isActive check

- The function `getUserVotingPower` is not used. If it's not used should be deleted.
- The function `getTotalVotingPower` is not used. If it's not used should be deleted

- I've deleted a bunch of code, make sure all events or errors are used, other wise delete them
