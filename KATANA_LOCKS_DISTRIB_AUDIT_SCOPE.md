# Katana Locks Distribution Audit Scope

## Final Commit Hash
This is the final commit hash meant to be audited for the updated encoder to enable ve-locks distribution for Katana: <br/>
[6a40cfb3bc7aa467eacad17a4a7fb0daf998c0d2](https://github.com/aragon/osx-capital-distributor/commit/6a40cfb3bc7aa467eacad17a4a7fb0daf998c0d2)


## Audit Scope

The audit scope is limited to the following contract:
- [VotingEscrowLockPayoutActionEncoder.sol](https://github.com/aragon/osx-capital-distributor/blob/6a40cfb3bc7aa467eacad17a4a7fb0daf998c0d2/src/payoutActionEncoders/VotingEscrowLockPayoutActionEncoder.sol)


## Relevant Test Files
- Unit: [tests/payoutActionEncoders/VotingEscrowLockPayoutActionEncoderTest.t.sol](https://github.com/aragon/osx-capital-distributor/blob/feat/katana-locks-distrib/tests/payoutActionEncoders/VotingEscrowLockPayoutActionEncoderTest.t.sol)
- Integration: [tests/integration/VotingEscrowLockPayoutLocalTest.t.sol](https://github.com/aragon/osx-capital-distributor/blob/feat/katana-locks-distrib/tests/integration/VotingEscrowLockPayoutLocalTest.t.sol)

## Out of Scope
- Everything else in the repo
- Including new files in the tests dir: [tests/deploy/SetupVe.sol](https://github.com/aragon/osx-capital-distributor/blob/feat/katana-locks-distrib/tests/deploy/SetupVe.sol) and [tests/utils/MerkleTreeBuilder.sol](https://github.com/aragon/osx-capital-distributor/blob/feat/katana-locks-distrib/tests/utils/MerkleTreeBuilder.sol)

## Change Description

The VaultDepositPayoutActionEncoder has been modified to enable the Katana DAO to create ve-locks for their users for KAT tokens on their behalf, using the CapitalDistributorPlugin. Essentially changing it to encode (approve() + createLockFor()) actions on VotingEscrow, from (approve() + deposit()) actions into a Vault. Find the diff [here](https://www.diffchecker.com/Acf6tAb5/) for reference.

All other functionalities and flows of the CapitalDistributorPlugin remain the same.