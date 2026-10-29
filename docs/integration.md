# Integrating Capital Distributor

This guide follows [CapitalDistributorPlugin](../src/CapitalDistributorPlugin.sol) and the included
[MerkleDistributorStrategy](../src/allocatorStrategies/MerkleDistributorStrategy.sol). The plugin pays from its OSx DAO;
campaign creation does not deposit funds or reserve a budget.

## Prepare a recipient list

For each campaign, determine one total entitlement per recipient, in the payout token's smallest units. The Merkle
strategy verifies leaves with this encoding:

```solidity
bytes32 leaf = keccak256(abi.encodePacked(recipient, totalEntitlement));
```

Proofs use sorted hash pairs through OpenZeppelin's `MerkleProof`. The [repository tools](../script/utils/README.md)
generate roots and proofs with that encoding. A generator using different leaf encoding or double-hashed leaves will
produce incompatible proofs.

The root commits to the recipient and amount. Campaign identity and token are supplied by the campaign configuration;
they are not fields in this leaf. Reusing a root in another campaign reuses its recipient entitlements with a separate
claimed-amount record.

## Create a campaign

The caller needs `CAMPAIGN_MANAGER_PERMISSION_ID` on the plugin. The setup grants this permission to the DAO, so the
usual creation path is an action executed through the DAO's governance plugin.

The deployment script registers the Merkle strategy as `bytes32("merkle-distributor-strategy")`. This is a padded string
identifier, not its hash. A custom factory can register a different ID.

```solidity
uint256 campaignId = plugin.createCampaign(
    bytes("ipfs://campaign-metadata"),
    ICapitalDistributorPlugin.StrategyConfig({
        strategyId: bytes32("merkle-distributor-strategy"),
        strategyParams: "",
        initData: abi.encode(merkleRoot)
    }),
    ICapitalDistributorPlugin.PayoutConfig({
        token: token,
        actionEncoderId: bytes32(0),
        actionEncoderInitData: ""
    }),
    ICapitalDistributorPlugin.CampaignSettings({
        startTime: 0,
        endTime: uint64(block.timestamp + 30 days)
    })
);
```

This example uses an installed `plugin`, an `IERC20 token`, a nonzero `bytes32 merkleRoot`, and the structs from
[ICapitalDistributorPlugin](../src/interfaces/ICapitalDistributorPlugin.sol). Encoder ID `bytes32(0)` selects the
plugin's direct-transfer path.

Campaign IDs start at zero. Metadata must be nonempty and the token address nonzero. A nonzero start must be at or after
the creation timestamp; a nonzero end must be in the future and after the start. Claims are allowed at the start
timestamp and stop at the end timestamp.

The factories reuse strategy and encoder instances for matching type ID, DAO, calling plugin, and deployment parameters.
Campaign-specific configuration, such as a Merkle root or vault address, is stored within those instances under the
campaign ID.

## Enable payouts and supply the funds

Installation returns an `ExecuteSelectorCondition` as helper `0`, initially with no allowed calls. The DAO must call
`allowSelectors` on that helper to authorize each payout target and selector:

| Payout path                     | Required calls                                                                             |
| ------------------------------- | ------------------------------------------------------------------------------------------ |
| Direct transfer, including fees | `transfer(address,uint256)` on the payout token                                            |
| Vault deposit                   | `approve(address,uint256)` on the payout token and `deposit(uint256,address)` on the vault |
| Vault deposit with a fee        | Both vault calls plus `transfer(address,uint256)` on the payout token                      |

The DAO needs enough of the payout token for the gross claim: the net recipient amount plus any fee. Campaigns share its
treasury balance. The execution condition authorizes calls by target and selector; it does not reserve campaign funds or
set a campaign spending cap.

The [execution-condition tests](../tests/integration/ExecuteConditionIntegrationTest.t.sol) demonstrate a blocked claim
and a successful claim after the DAO allows the token's transfer selector.

## Submit and quote a claim

For a direct-transfer campaign:

```solidity
bytes memory strategyData = abi.encode(merkleProof, totalEntitlement);
uint256 netAmount = plugin.claimCampaignPayout(
    campaignId,
    recipient,
    strategyData,
    ""
);
```

`merkleProof` is a `bytes32[]`. Anyone can submit this call for `recipient`; it pays that recipient and records their
claimed total. To redirect an allocation, its holder calls `claimCampaignPayoutToAddress` with the destination and their
own proof. That method checks entitlement for `msg.sender`, not the destination address.

| Query                                                    | What it returns                                                                        |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `getCampaign(campaignId)`                                | Campaign configuration and stored state                                                |
| `isCampaignActive(campaignId)`                           | Whether state and time bounds currently permit claims                                  |
| `getCampaignPayout(campaignId, recipient, strategyData)` | Total entitlement reported by the strategy, before subtracting previous claims or fees |
| `getClaimedAmount(campaignId, recipient)`                | Gross entitlement already consumed by claims                                           |
| Strategy's `getFeeConfiguration()`                       | Fee recipient and rate in basis points                                                 |

The newly claimable amount is total entitlement minus the previously claimed amount. A configured fee is calculated on
that difference and rounded up to the next token unit. For a 1,000-unit claim at 250 basis points, the recipient gets
975 units and the fee recipient gets 25. The claimed record increases by 1,000.

A successful quote does not test campaign timing, DAO funds, or execution permissions. Simulating the claim checks that
complete path against the queried chain state.

`batchClaimCampaignPayout` takes four parallel arrays: campaign IDs, recipients, strategy data, and encoder data. It
accepts at most 50 entries. Any reverting entry reverts the whole batch, including earlier entries.

`PayoutClaimed` records the entitlement holder and net amount. For a redirected claim, the holder in the event differs
from the destination; the event does not include that destination.

## Update entitlements

For an existing Merkle campaign, the DAO can:

1. Call `pauseCampaign(campaignId)` on the plugin.
2. Publish a replacement recipient list and proofs with cumulative total entitlements.
3. Call `updateCampaignMerkleRoot(campaignId, abi.encode(newRoot))` on the campaign's strategy.
4. Call `resumeCampaign(campaignId)` on the plugin.

The root update requires the strategy owner or DAO and a nonzero root different from the current root. It also requires
`isCampaignPaused(campaignId)` to return true, which includes the campaign's time bounds. A campaign paused before its
start therefore cannot update its root until the start, and an expired campaign cannot use this update path.

Updating the root preserves claimed amounts. Lowering an entitlement below what the recipient has claimed does not
recover a payment; the plugin rejects another claim while the recorded amount is at least the new entitlement.

`endCampaign` permanently disables claims and has no resume path. Expiration disables claims through the time check
without changing the stored state to `ENDED`.

## Use a vault payout

The deployment script registers `bytes32("vault-deposit-encoder")`. Select that ID and pass `abi.encode(vaultAddress)`
as `actionEncoderInitData` when creating the campaign. The encoder builds an approval for the net amount and a call to
`deposit(netAmount, payoutAddress)`; the DAO executes both calls. A fee, when configured, is a separate token transfer.

The included encoder has no minimum-output parameter and does not validate the vault's asset. Its `setupCampaign` method
can replace the campaign vault when called by the encoder owner or DAO, changing the destination for subsequent
deposits.

Source: [vault encoder](../src/payoutActionEncoders/VaultDepositPayoutActionEncoder.sol).
