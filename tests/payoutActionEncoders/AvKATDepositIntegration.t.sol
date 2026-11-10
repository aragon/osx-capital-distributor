// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { IPluginSetup } from "@aragon/commons/plugin/setup/IPluginSetup.sol";
import { ExecuteSelectorCondition } from "@aragon/conditions/ExecuteSelectorCondition.sol";
import { CapitalDistributorPlugin } from "../../src/CapitalDistributorPlugin.sol";
import { CapitalDistributorPluginSetup } from "../../src/CapitalDistributorPluginSetup.sol";
import { ICapitalDistributorPlugin } from "../../src/interfaces/ICapitalDistributorPlugin.sol";
import { AllocatorStrategyFactory } from "../../src/factories/AllocatorStrategyFactory.sol";
import { ActionEncoderFactory } from "../../src/factories/ActionEncoderFactory.sol";
import { VaultDepositPayoutActionEncoder } from "../../src/payoutActionEncoders/VaultDepositPayoutActionEncoder.sol";
import { MerkleDistributorStrategy } from "../../src/allocatorStrategies/MerkleDistributorStrategy.sol";
import { MintableERC20 } from "../mocks/MintableERC20.sol";
import { ERC4626Mock } from "../mocks/ERC4626Mock.sol";

/// @dev Shared fixture uses the real plugin setup, factories, DAO and selector condition.
///      Allocations use a real two-leaf Merkle campaign; no vault calls are mocked on the fork.
abstract contract AvKATDepositFixture is Test {
    bytes32 internal constant ENCODER_ID = bytes32("vault-deposit-encoder");
    bytes32 internal constant STRATEGY_ID = bytes32("avkat-test-allocation");
    uint256 internal allocation = 1 ether;

    DAO internal dao;
    CapitalDistributorPlugin internal plugin;
    ExecuteSelectorCondition internal condition;
    AllocatorStrategyFactory internal strategies;
    IERC4626 internal vault;
    IERC20 internal asset;
    address internal recipient;
    address internal secondRecipient;
    address internal feeRecipient;
    uint256 internal campaignId;

    function _install(IERC4626 targetVault, uint32 feeBasisPoints) internal {
        vault = targetVault;
        asset = IERC20(vault.asset());
        recipient = makeAddr("avkat-recipient");
        secondRecipient = makeAddr("second-recipient");
        feeRecipient = makeAddr("avkat-fee-recipient");

        dao = DAO(
            payable(address(
                    new ERC1967Proxy(
                        address(new DAO()), abi.encodeCall(DAO.initialize, (bytes(""), address(this), address(0), ""))
                    )
                ))
        );
        strategies = new AllocatorStrategyFactory();
        ActionEncoderFactory encoders = new ActionEncoderFactory();
        encoders.registerActionEncoder(ENCODER_ID, address(new VaultDepositPayoutActionEncoder()), "");
        strategies.registerStrategyType(
            STRATEGY_ID, address(new MerkleDistributorStrategy()), "", feeRecipient, feeBasisPoints
        );

        CapitalDistributorPluginSetup setup = new CapitalDistributorPluginSetup();
        (address pluginAddress, IPluginSetup.PreparedSetupData memory prepared) =
            setup.prepareInstallation(address(dao), abi.encode(address(strategies), address(encoders)));
        plugin = CapitalDistributorPlugin(pluginAddress);
        dao.applyMultiTargetPermissions(prepared.permissions);
        condition = ExecuteSelectorCondition(prepared.helpers[0]);

        _allow(address(asset), IERC20.approve.selector);
        _allow(address(vault), IERC4626.deposit.selector);
        if (feeBasisPoints > 0) _allow(address(asset), IERC20.transfer.selector);

        vm.prank(address(dao));
        campaignId = plugin.createCampaign(
            "ipfs://avkat-deposit-test",
            ICapitalDistributorPlugin.StrategyConfig(STRATEGY_ID, "", abi.encode(_root())),
            ICapitalDistributorPlugin.PayoutConfig(asset, ENCODER_ID, abi.encode(address(vault))),
            ICapitalDistributorPlugin.CampaignSettings(0, 0)
        );
    }

    function _leaf(address receiver) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(receiver, allocation));
    }

    function _root() internal view returns (bytes32) {
        bytes32 a = _leaf(recipient);
        bytes32 b = _leaf(secondRecipient);
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _proof(address receiver) internal view returns (bytes memory) {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = _leaf(receiver == recipient ? secondRecipient : recipient);
        return abi.encode(proof, allocation);
    }

    function _allow(address target, bytes4 selector) internal {
        ExecuteSelectorCondition.SelectorTarget memory entry =
            ExecuteSelectorCondition.SelectorTarget(target, new bytes4[](1));
        entry.selectors[0] = selector;
        vm.prank(address(dao));
        condition.allowSelectors(entry);
    }

    function _fund(uint256 amount) internal {
        // Test-only funding of our newly deployed DAO; no live transaction is sent.
        deal(address(asset), address(dao), amount);
    }

    function _assertClaim(address receiver, uint256 expectedFee) internal {
        uint256 depositAmount = allocation - expectedFee;
        uint256 expectedShares = vault.previewDeposit(depositAmount);
        assertGt(expectedShares, 0, "Deposit must mint shares");
        uint256 sharesBefore = vault.balanceOf(receiver);
        uint256 assetsBefore = vault.totalAssets();
        uint256 treasuryBefore = asset.balanceOf(address(dao));
        uint256 receiverAssetsBefore = asset.balanceOf(receiver);
        uint256 feesBefore = asset.balanceOf(feeRecipient);

        vm.prank(receiver);
        uint256 paid = plugin.claimCampaignPayout(campaignId, receiver, _proof(receiver), "");

        assertEq(paid, depositAmount, "Claim returns underlying assets after fees");
        assertEq(vault.balanceOf(receiver) - sharesBefore, expectedShares, "Claimant receives previewed avKAT shares");
        assertEq(vault.totalAssets() - assetsBefore, depositAmount, "Vault accounts for deposited KAT");
        assertEq(treasuryBefore - asset.balanceOf(address(dao)), allocation, "DAO funds the entire claim");
        assertEq(asset.balanceOf(receiver), receiverAssetsBefore, "Claimant receives shares rather than raw KAT");
        assertEq(asset.balanceOf(feeRecipient) - feesBefore, expectedFee, "Fee paid separately in KAT");
        assertEq(asset.allowance(address(dao), address(vault)), 0, "Deposit consumes exact approval");
        assertEq(vault.balanceOf(address(dao)), 0, "DAO does not retain shares");
        assertEq(vault.balanceOf(address(plugin)), 0, "Plugin does not retain shares");
        assertEq(asset.balanceOf(address(plugin)), 0, "Plugin does not custody KAT");
        assertEq(plugin.getClaimedAmount(campaignId, receiver), allocation, "Accounting uses gross KAT allocation");
    }

    function _assertFailedClaimLeavesNoState() internal view {
        assertEq(asset.balanceOf(address(dao)), allocation, "DAO funds preserved");
        assertEq(asset.allowance(address(dao), address(vault)), 0, "Approval rolled back");
        assertEq(vault.balanceOf(recipient), 0, "No shares minted");
        assertEq(plugin.getClaimedAmount(campaignId, recipient), 0, "Claim accounting rolled back");
    }
}

/// @notice Local ERC4626 compatibility tests; these do not model avKAT's escrow/strategy internals.
contract AvKATDepositLocalTest is AvKATDepositFixture {
    function setUp() public {
        MintableERC20 kat = new MintableERC20();
        _install(IERC4626(address(new ERC4626Mock(address(kat)))), 0);
        _fund(allocation);
    }

    function test_LocalClaimMintsSharesToRecipient() public {
        _assertClaim(recipient, 0);
    }

    function test_LocalClaimAtNonUnitSharePrice() public {
        MintableERC20(address(asset)).mint(address(this), 10 ether);
        asset.approve(address(vault), 10 ether);
        vault.deposit(10 ether, address(this));
        // Simulate accrued yield to ensure assertions distinguish assets from shares.
        MintableERC20(address(asset)).mint(address(vault), 5 ether);
        assertLt(vault.previewDeposit(allocation), allocation);
        _assertClaim(recipient, 0);
    }

    function test_LocalClaimWithFee() public {
        _install(vault, 300);
        _fund(allocation);
        _assertClaim(recipient, 0.03 ether);
    }

    function test_LocalRepeatedClaimsForDifferentRecipients() public {
        _fund(2 * allocation);
        _assertClaim(recipient, 0);
        _assertClaim(secondRecipient, 0);
    }

    function test_LocalCannotClaimTwice() public {
        _assertClaim(recipient, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.AlreadyClaimedMaxAmount.selector, campaignId, recipient, allocation, allocation
            )
        );
        plugin.claimCampaignPayout(campaignId, recipient, _proof(recipient), "");
    }

    function test_LocalRequiresVaultDepositPermission() public {
        ExecuteSelectorCondition.SelectorTarget memory entry =
            ExecuteSelectorCondition.SelectorTarget(address(vault), new bytes4[](1));
        entry.selectors[0] = IERC4626.deposit.selector;
        vm.prank(address(dao));
        condition.disallowSelectors(entry);

        vm.expectRevert();
        plugin.claimCampaignPayout(campaignId, recipient, _proof(recipient), "");
        _assertFailedClaimLeavesNoState();
    }

    function test_LocalDepositRevertRollsBackApprovalAndClaim() public {
        // A wrong campaign asset makes the vault fail to pull its actual underlying.
        MintableERC20 wrongAsset = new MintableERC20();
        _allow(address(wrongAsset), IERC20.approve.selector);
        vm.prank(address(dao));
        campaignId = plugin.createCampaign(
            "ipfs://wrong-asset",
            ICapitalDistributorPlugin.StrategyConfig(STRATEGY_ID, "", abi.encode(_root())),
            ICapitalDistributorPlugin.PayoutConfig(IERC20(address(wrongAsset)), ENCODER_ID, abi.encode(address(vault))),
            ICapitalDistributorPlugin.CampaignSettings(0, 0)
        );
        wrongAsset.mint(address(dao), allocation);
        vm.expectRevert();
        plugin.claimCampaignPayout(campaignId, recipient, _proof(recipient), "");
        _assertFailedClaimLeavesNoState();
        assertEq(wrongAsset.allowance(address(dao), address(vault)), 0);
        assertEq(wrongAsset.balanceOf(address(dao)), allocation);
    }
}

interface IAvKATState {
    function paused() external view returns (bool);
    function escrow() external view returns (address);
}

interface IAvKATEscrowState {
    function minDeposit() external view returns (uint256);
}

/// @notice Opt-in tests against the actual Katana vault, with a fresh DAO/plugin on the fork.
/// @dev Reproduce with:
/// KATANA_RPC_URL=https://rpc.katana.network AVKAT_FORK_BLOCK=47556901 \
/// forge test --match-contract AvKATDepositForkTest -vv
/// Normal offline runs skip these tests. Funding uses deal; this never broadcasts transactions.
contract AvKATDepositForkTest is AvKATDepositFixture {
    address internal constant AVKAT = 0x7231dbaCdFc968E07656D12389AB20De82FbfCeB;
    address internal constant KAT = 0x7F1f4b4b29f5058fA32CC7a97141b8D7e5ABDC2d;
    bool internal forkEnabled;
    uint256 internal minimumDeposit;

    function setUp() public {
        string memory rpc = vm.envOr("KATANA_RPC_URL", string(""));
        forkEnabled = bytes(rpc).length > 0;
        if (!forkEnabled) return;
        uint256 forkBlock = vm.envOr("AVKAT_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) vm.createSelectFork(rpc);
        else vm.createSelectFork(rpc, forkBlock);

        assertEq(block.chainid, 747_474, "Expected Katana mainnet");
        assertEq(IERC4626(AVKAT).asset(), KAT, "Verify campaign asset against deployed vault");
        assertFalse(IAvKATState(AVKAT).paused(), "Vault must accept deposits");
        emit log_named_uint("Katana fork block", block.number);
        minimumDeposit = IAvKATEscrowState(IAvKATState(AVKAT).escrow()).minDeposit();
        emit log_named_uint("Minimum KAT deposit (base units)", minimumDeposit);
        allocation = 1000 ether;
        assertGe(allocation * 97 / 100, minimumDeposit, "Test amount must cover minimum after fees");
        _install(IERC4626(AVKAT), 0);
        _fund(allocation);
    }

    function test_ForkClaimMintsAvKAT() public {
        vm.skip(!forkEnabled);
        _assertClaim(recipient, 0);
    }

    function test_ForkClaimWithFee() public {
        vm.skip(!forkEnabled);
        _install(vault, 300);
        _fund(allocation);
        _assertClaim(recipient, 30 ether);
    }

    function test_ForkRepeatedDeposits() public {
        vm.skip(!forkEnabled);
        _fund(2 * allocation);
        _assertClaim(recipient, 0);
        _assertClaim(secondRecipient, 0);
    }

    function test_ForkExactMinimumDeposit() public {
        vm.skip(!forkEnabled);
        allocation = minimumDeposit;
        _install(vault, 0);
        _fund(allocation);
        _assertClaim(recipient, 0);
    }

    function test_ForkBelowMinimumRevertsAtomically() public {
        vm.skip(!forkEnabled);
        assertGt(minimumDeposit, 1);
        allocation = minimumDeposit - 1;
        _install(vault, 0);
        _fund(allocation);
        uint256 assetsBefore = vault.totalAssets();
        vm.expectRevert(abi.encodeWithSelector(DAO.ActionFailed.selector, uint256(1)));
        plugin.claimCampaignPayout(campaignId, recipient, _proof(recipient), "");
        _assertFailedClaimLeavesNoState();
        assertEq(vault.totalAssets(), assetsBefore);
    }

    function test_ForkFeeCannotPushDepositBelowMinimum() public {
        vm.skip(!forkEnabled);
        allocation = minimumDeposit;
        _install(vault, 300);
        _fund(allocation);
        uint256 assetsBefore = vault.totalAssets();
        vm.expectRevert(abi.encodeWithSelector(DAO.ActionFailed.selector, uint256(1)));
        plugin.claimCampaignPayout(campaignId, recipient, _proof(recipient), "");
        _assertFailedClaimLeavesNoState();
        assertEq(vault.totalAssets(), assetsBefore);
        assertEq(asset.balanceOf(feeRecipient), 0, "No fee paid on failed deposit");
    }
}
