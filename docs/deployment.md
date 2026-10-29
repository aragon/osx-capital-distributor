# Deployment and installation

This guide follows [Deploy.s.sol](../script/Deploy.s.sol) and
[CapitalDistributorPluginSetup](../src/CapitalDistributorPluginSetup.sol). The script publishes a plugin repository and
creates a new DAO with Capital Distributor and an Admin plugin. Its `ADMIN_OWNER` controls that Admin plugin.

## Configure the script

Install the dependencies and build as described in the [README](../README.md#local-development), then copy
[.env.example](../.env.example) to a local `.env`. Required addresses must refer to the selected chain's OSx and Admin
plugin deployments; this repository does not maintain a verified deployment-address registry.

| Variable              | Use                                                                       |
| --------------------- | ------------------------------------------------------------------------- |
| `CHAIN_NAME`          | RPC URL or alias passed to `vm.createSelectFork`                          |
| `PLUGIN_REPO_FACTORY` | Existing OSx plugin-repository factory                                    |
| `DAO_FACTORY`         | Existing OSx DAO factory                                                  |
| `ADMIN_REPO`          | Existing Admin plugin repository; the script selects release 1, build 2   |
| `ADMIN_OWNER`         | Initial owner of the installed Admin plugin                               |
| `PLUGIN_MAINTAINER`   | Maintainer of the new Capital Distributor plugin repository               |
| `PLUGIN_NAME`         | Optional repository subdomain; defaults to a timestamp-based name         |
| `DAO_NAME`, `DAO_URI` | Optional DAO subdomain and URI; defaults are generated from the timestamp |
| `FEE_RECIPIENT`       | Optional strategy fee recipient; defaults to zero                         |
| `FEE_BASIS_POINTS`    | Optional fee rate; defaults to zero, maximum 1,000 (10%)                  |

A nonzero fee requires a nonzero recipient. The script casts the fee rate to `uint32` before registration; configure it
within the documented range of 0 through 1,000. Keep signing credentials out of committed configuration.

[foundry.toml](../foundry.toml) defines RPC aliases. Its `mainnet` and `sepolia` aliases require `API_KEY_ALCHEMY`;
source verification uses `API_KEY_ETHERSCAN`. The script selects its fork from `CHAIN_NAME` in both setup and execution,
so that variable must identify the intended chain even when a command also supplies `--rpc-url`.

## Simulate before broadcasting

Create the directory used for deployment records. Export the variables referenced by shell arguments; Foundry reads the
remaining script variables from `.env`.

```sh
mkdir -p deployments
export CHAIN_NAME=sepolia
export DEPLOYER_ADDRESS=0xYourDeployerAddress
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$CHAIN_NAME" \
  --sender "$DEPLOYER_ADDRESS" \
  -vvv
```

Replace the address placeholder with the account that will broadcast. The simulation checks the configured dependencies,
repository publication, and both plugin installations against the selected network.

The script deploys two registries, registers the Merkle strategy and vault encoder, deploys the plugin setup, publishes
release 1/build 1, and asks the DAO factory to create the organization. It writes its result to
`deployments/deployment-<chainId>-<timestamp>.json`, including during a simulation. A simulation record describes
predicted addresses; broadcast receipts establish what was deployed.

To broadcast the same reviewed configuration with an account stored in a Foundry keystore:

```sh
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$CHAIN_NAME" \
  --account deployer \
  --broadcast \
  -vvv
```

Here `deployer` is the name of the configured keystore account. The Makefile also provides `deploy-dry` and `deploy`
targets, which pass `PRIVATE_KEY` on the command line; they use `CHAIN_NAME` through the script rather than the
Makefile's `RPC_URL` variable.

## Installing into an existing DAO

`prepareInstallation` accepts `abi.encode(strategyFactory, actionEncoderFactory)` and rejects zero factory addresses. It
deploys the plugin proxy and execution-condition helper, then returns the permission changes for the OSx installation
process to apply. Calling it alone does not apply those permissions.

| Target                     | Who receives authority           | Permission                       |
| -------------------------- | -------------------------------- | -------------------------------- |
| Plugin                     | DAO                              | `CAMPAIGN_MANAGER_PERMISSION_ID` |
| Plugin                     | DAO                              | `SET_METADATA_PERMISSION_ID`     |
| Plugin                     | DAO                              | `UPGRADE_PLUGIN_PERMISSION_ID`   |
| DAO                        | Plugin, subject to the condition | `EXECUTE_PERMISSION_ID`          |
| Execution-condition helper | DAO                              | `MANAGE_SELECTORS_PERMISSION_ID` |

The helper is returned at `preparedSetupData.helpers[0]`. Its allowed-call set is empty at installation. The DAO must
authorize the target and selector of each token transfer, token approval, and vault deposit needed by its campaigns. The
[integration guide](integration.md#enable-payouts-and-supply-the-funds) lists those calls by payout path.

The DAO receives upgrade authority over the plugin. This setup's `prepareUpdate` reverts with `NotImplemented`.

## Confirm the deployment

Record the repository commit, chain, deployment transactions, DAO, plugin proxy and implementation, setup, factories,
and execution-condition helper. Compare the installed permissions with the table above and confirm who controls the
Admin plugin or other governance mechanism.

Read each selected factory ID's implementation and, for strategies, its fee configuration. Registration is
permissionless and IDs cannot be overwritten. The supplied deployment script creates fresh registries and registers its
implementations before installing the plugin.

Before funding a campaign, simulate its actual creation and claim path with the intended token, recipient proof, fees,
and allowed calls. Direct payouts encode `IERC20.transfer` as a DAO action; the plugin does not decode its boolean
return value. Campaign creation tests whether a `transferFrom` static call from the zero address reverts, but that check
does not establish that every failed payout will revert.

For a vault campaign, the claim simulation also exercises approval, deposit, and the separate fee transfer. The encoder
does not check the vault's underlying asset or enforce a minimum output.

Tests for these paths are in [the plugin tests](../tests/CapitalDistributorPluginTest.t.sol),
[execution-condition tests](../tests/integration/ExecuteConditionIntegrationTest.t.sol), and
[vault encoder tests](../tests/payoutActionEncoders/VaultDepositPayoutActionEncoderTest.t.sol).
