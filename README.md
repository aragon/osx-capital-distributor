# Capital Distributor [![Github Actions][gha-badge]][gha] [![Foundry][foundry-badge]][foundry] [![License: AGPL v3][license-badge]][license]

[gha]: https://github.com/aragon/osx-capital-distributor/actions
[gha-badge]: https://github.com/aragon/osx-capital-distributor/actions/workflows/ci.yml/badge.svg
[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[license]: https://www.gnu.org/licenses/agpl-3.0
[license-badge]: https://img.shields.io/badge/License-AGPL%20v3-blue.svg

Capital Distributor is an Aragon OSx plugin for claimable token distributions from a DAO treasury. It includes a Merkle
allocation strategy, direct token transfers, and a vault deposit encoder.

## Documentation

User and developer guides live in [protocol-doc](https://github.com/aragon/protocol-doc). Start with the
[Distributor overview](https://github.com/aragon/protocol-doc/blob/main/plugins/capital-distributor.md) or the
[Merkle campaign walkthrough](https://github.com/aragon/protocol-doc/blob/main/guides/distribute-tokens.md). Component
references cover
[campaigns and fees](https://github.com/aragon/protocol-doc/blob/main/plugins/capital-distributor/campaigns.md),
[Merkle allocations](https://github.com/aragon/protocol-doc/blob/main/plugins/capital-distributor/merkle-allocations.md),
[payout actions](https://github.com/aragon/protocol-doc/blob/main/plugins/capital-distributor/payouts.md), and
[installation permissions](https://github.com/aragon/protocol-doc/blob/main/plugins/capital-distributor/setup.md).

This repository covers the source, build, tests, deployment script, and Merkle tooling.

## Technical stack and source

The contracts use Solidity 0.8.29, the Aragon OSx plugin framework, and OpenZeppelin 4.9.6. The plugin uses UUPS
upgrades authorized through the DAO. Foundry builds and tests the contracts; Bun installs Solidity dependencies into
`node_modules` from the checked-in lockfile.

| Component                                 | Source                                                                                          |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Campaign and claim execution              | [CapitalDistributorPlugin](src/CapitalDistributorPlugin.sol)                                    |
| Merkle allocation strategy                | [MerkleDistributorStrategy](src/allocatorStrategies/MerkleDistributorStrategy.sol)              |
| Vault deposit encoder                     | [VaultDepositPayoutActionEncoder](src/payoutActionEncoders/VaultDepositPayoutActionEncoder.sol) |
| Implementation registration and instances | [Factories](src/factories/)                                                                     |
| Installation and permissions              | [CapitalDistributorPluginSetup](src/CapitalDistributorPluginSetup.sol)                          |

## Local development

Install [Foundry v1.3.0](https://getfoundry.sh/) to match CI, [Bun](https://bun.sh/), and Git.

```sh
git clone https://github.com/aragon/osx-capital-distributor.git
cd osx-capital-distributor
bun install --frozen-lockfile
forge build
forge test
```

| Command                   | Purpose                                           |
| ------------------------- | ------------------------------------------------- |
| `bun run lint`            | Check Solidity formatting and Prettier formatting |
| `forge test -vvv`         | Run tests with detailed failure output            |
| `forge coverage`          | Generate a coverage summary                       |
| `forge test --gas-report` | Report gas used by tested calls                   |

The [CI workflow](.github/workflows/ci.yml) uses the `ci` profile, which raises fuzz runs from 1,000 to 10,000.

## Guides and source

| Goal                                                          | Read                                                                                                                                     |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Create campaigns, serve proofs, and integrate claims          | [Campaign walkthrough](https://github.com/aragon/protocol-doc/blob/main/guides/distribute-tokens.md)                                     |
| Configure deployment, installation, and execution permissions | [Deployment guide](docs/deployment.md)                                                                                                   |
| Generate Merkle roots and proof files                         | [Merkle tools](script/utils/README.md)                                                                                                   |
| Look up campaign structs and external methods                 | [Plugin interface](src/interfaces/ICapitalDistributorPlugin.sol)                                                                         |
| Extend allocation or payout behavior                          | [Strategy base](src/allocatorStrategies/AllocatorStrategyBase.sol), [encoder base](src/payoutActionEncoders/PayoutActionEncoderBase.sol) |
| Review tests                                                  | [Test directory](tests/)                                                                                                                 |
| Review audit material                                         | [Audit directory](audits/)                                                                                                               |

Audit reports apply to their stated code revisions and scope. The directory also contains a report for a voting-escrow
payout encoder, which is not included in this checkout's `src/payoutActionEncoders/` directory.

## License

[GNU Affero General Public License v3.0 or later](LICENSE.md).
