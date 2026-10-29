# Integrating Capital Distributor

The
[Merkle campaign walkthrough in protocol-doc](https://github.com/aragon/protocol-doc/blob/main/guides/distribute-tokens.md)
covers proof generation, campaign creation, claims, and cumulative root updates.

Use the component references for
[campaign accounting and fees](https://github.com/aragon/protocol-doc/blob/main/plugins/capital-distributor/campaigns.md),
[Merkle encoding](https://github.com/aragon/protocol-doc/blob/main/plugins/capital-distributor/merkle-allocations.md),
and [installation permissions](https://github.com/aragon/protocol-doc/blob/main/plugins/capital-distributor/setup.md).

## Enable payouts and supply the funds

The [payout action reference](https://github.com/aragon/protocol-doc/blob/main/plugins/capital-distributor/payouts.md)
lists the token and vault calls to authorize. The DAO must hold the payout tokens; campaign creation does not reserve a
budget.

Repository-specific instructions remain in the [deployment guide](deployment.md) and
[Merkle tools reference](../script/utils/README.md).
