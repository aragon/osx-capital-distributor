// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Test, console2 } from "forge-std/Test.sol";
import { AragonTest } from "./helpers/AragonTest.sol";
import { MintableERC20 } from "./mocks/MintableERC20.sol";
import { CapitalDistributorPlugin } from "../src/CapitalDistributorPlugin.sol";
import { CapitalDistributorPluginSetup } from "../src/CapitalDistributorPluginSetup.sol";
import { AllocatorStrategyFactory } from "../src/factories/AllocatorStrategyFactory.sol";
import { ActionEncoderFactory } from "../src/factories/ActionEncoderFactory.sol";
import { MerkleDistributorStrategy } from "../src/allocatorStrategies/MerkleDistributorStrategy.sol";
import { VaultDepositPayoutActionEncoder } from "../src/payoutActionEncoders/VaultDepositPayoutActionEncoder.sol";
import { AllocatorStrategyBase } from "../src/allocatorStrategies/AllocatorStrategyBase.sol";
import { PayoutActionEncoderBase } from "../src/payoutActionEncoders/PayoutActionEncoderBase.sol";
import { IAllocatorStrategy } from "../src/interfaces/IAllocatorStrategy.sol";
import { IPayoutActionEncoder } from "../src/interfaces/IPayoutActionEncoder.sol";
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { IPluginRepo } from "@aragon/osx/framework/plugin/repo/IPluginRepo.sol";

contract OwnerOrDaoTest is AragonTest {
    MintableERC20 token;
    CapitalDistributorPlugin capitalDistributorPlugin;

    function setUp() public {
        // Deploy token
        token = new MintableERC20();

        // Use the plugin already deployed by AragonTest
        capitalDistributorPlugin = CapitalDistributorPlugin(pluginAddress[0]);

        // Register the strategies we need for testing
        vm.startPrank(address(createdDao));

        // Register merkle strategy
        allocatorStrategyFactory.registerStrategyType(
            toBytes32("merkle-strategy"),
            address(new MerkleDistributorStrategy()),
            "Merkle Distributor Strategy",
            address(0), // No fee recipient
            0 // No fee
        );

        // Register vault encoder
        actionEncoderFactory.registerActionEncoder(
            toBytes32("vault-encoder"), address(new VaultDepositPayoutActionEncoder()), "Vault Deposit Payout Encoder"
        );

        vm.stopPrank();
    }

    // =========================================================================
    // MerkleDistributorStrategy OwnerOrDao Tests
    // =========================================================================

    function test_MerkleStrategy_SetAllocationCampaign_AsOwner() public {
        // Deploy strategy
        vm.prank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);

        // Owner should be able to call setAllocationCampaign
        bytes32 merkleRoot = keccak256("test-merkle-root");

        vm.prank(strategy.owner());
        strategy.setAllocationCampaign(1, abi.encode(merkleRoot));

        assertEq(strategy.getCampaignMerkleRoot(1), merkleRoot);
    }

    function test_MerkleStrategy_SetAllocationCampaign_AsDao() public {
        // Deploy strategy
        vm.prank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);

        // DAO should be able to call setAllocationCampaign
        bytes32 merkleRoot = keccak256("test-merkle-root");

        vm.prank(address(createdDao));
        strategy.setAllocationCampaign(2, abi.encode(merkleRoot));

        assertEq(strategy.getCampaignMerkleRoot(2), merkleRoot);
    }

    function test_MerkleStrategy_SetAllocationCampaign_RevertUnauthorized() public {
        // Deploy strategy
        vm.prank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);

        // Bob without permission should not be able to call
        bytes32 merkleRoot = keccak256("test-merkle-root");

        vm.expectRevert(abi.encodeWithSelector(IAllocatorStrategy.NotAuthorized.selector, bob));
        vm.prank(bob);
        strategy.setAllocationCampaign(3, abi.encode(merkleRoot));
    }

    function test_MerkleStrategy_UpdateMerkleRoot_AsOwner() public {
        // Setup campaign first
        vm.startPrank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);

        token.mint(address(createdDao), 10 ether);

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://metadata",
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), "", abi.encode(keccak256("initial-root"))
            ),
            CapitalDistributorPlugin.PayoutConfig(token, bytes32(0), ""),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        // Pause campaign
        capitalDistributorPlugin.pauseCampaign(campaignId);
        vm.stopPrank();

        // Owner updates merkle root
        bytes32 newRoot = keccak256("new-merkle-root");
        vm.prank(strategy.owner());
        strategy.updateCampaignMerkleRoot(campaignId, abi.encode(newRoot));

        assertEq(strategy.getCampaignMerkleRoot(campaignId), newRoot);
    }

    function test_MerkleStrategy_UpdateMerkleRoot_AsDao() public {
        // Setup campaign
        vm.startPrank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);

        token.mint(address(createdDao), 10 ether);

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://metadata",
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), "", abi.encode(keccak256("initial-root"))
            ),
            CapitalDistributorPlugin.PayoutConfig(token, bytes32(0), ""),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );

        capitalDistributorPlugin.pauseCampaign(campaignId);

        // DAO updates merkle root
        bytes32 newRoot = keccak256("dao-new-root");
        strategy.updateCampaignMerkleRoot(campaignId, abi.encode(newRoot));

        assertEq(strategy.getCampaignMerkleRoot(campaignId), newRoot);
        vm.stopPrank();
    }

    function test_MerkleStrategy_RenounceOwnership_AsOwner() public {
        vm.prank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);

        address initialOwner = strategy.owner();

        vm.prank(initialOwner);
        strategy.renounceOwnership();

        assertEq(strategy.owner(), address(0));
    }

    function test_MerkleStrategy_RenounceOwnership_AsDao() public {
        vm.startPrank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);
        vm.stopPrank();

        // DAO can renounce ownership
        vm.prank(address(createdDao));
        strategy.renounceOwnership();

        assertEq(strategy.owner(), address(0));
    }

    function test_MerkleStrategy_TransferOwnership_AsOwner() public {
        vm.prank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);

        address initialOwner = strategy.owner();

        vm.prank(initialOwner);
        strategy.transferOwnership(bob);

        assertEq(strategy.owner(), bob);
    }

    function test_MerkleStrategy_TransferOwnership_AsDao() public {
        vm.startPrank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);
        vm.stopPrank();

        // DAO can transfer ownership
        vm.prank(address(createdDao));
        strategy.transferOwnership(carol);

        assertEq(strategy.owner(), carol);
    }

    // =========================================================================
    // VaultDepositPayoutActionEncoder OwnerOrDao Tests
    // =========================================================================

    function test_VaultEncoder_SetupCampaign_AsOwner() public {
        vm.prank(address(createdDao));
        VaultDepositPayoutActionEncoder encoder = VaultDepositPayoutActionEncoder(
            address(capitalDistributorPlugin.deployActionEncoder(toBytes32("vault-encoder"), ""))
        );

        address vault = makeAddr("vault");

        vm.prank(encoder.owner());
        encoder.setupCampaign(1, abi.encode(vault));

        assertEq(encoder.campaignVaults(1), vault);
    }

    function test_VaultEncoder_SetupCampaign_AsDao() public {
        vm.prank(address(createdDao));
        VaultDepositPayoutActionEncoder encoder = VaultDepositPayoutActionEncoder(
            address(capitalDistributorPlugin.deployActionEncoder(toBytes32("vault-encoder"), ""))
        );

        address vault = makeAddr("vault");

        vm.prank(address(createdDao));
        encoder.setupCampaign(2, abi.encode(vault));

        assertEq(encoder.campaignVaults(2), vault);
    }

    function test_VaultEncoder_SetupCampaign_RevertUnauthorized() public {
        vm.prank(address(createdDao));
        VaultDepositPayoutActionEncoder encoder = VaultDepositPayoutActionEncoder(
            address(capitalDistributorPlugin.deployActionEncoder(toBytes32("vault-encoder"), ""))
        );

        address vault = makeAddr("vault");

        vm.expectRevert(abi.encodeWithSelector(IPayoutActionEncoder.NotAuthorized.selector, bob));
        vm.prank(bob);
        encoder.setupCampaign(3, abi.encode(vault));
    }

    function test_VaultEncoder_RenounceOwnership_AsOwner() public {
        vm.prank(address(createdDao));
        VaultDepositPayoutActionEncoder encoder = VaultDepositPayoutActionEncoder(
            address(capitalDistributorPlugin.deployActionEncoder(toBytes32("vault-encoder"), ""))
        );

        address initialOwner = encoder.owner();

        vm.prank(initialOwner);
        encoder.renounceOwnership();

        assertEq(encoder.owner(), address(0));
    }

    function test_VaultEncoder_RenounceOwnership_AsDao() public {
        vm.startPrank(address(createdDao));
        VaultDepositPayoutActionEncoder encoder = VaultDepositPayoutActionEncoder(
            address(capitalDistributorPlugin.deployActionEncoder(toBytes32("vault-encoder"), ""))
        );
        vm.stopPrank();

        // DAO can renounce ownership
        vm.prank(address(createdDao));
        encoder.renounceOwnership();

        assertEq(encoder.owner(), address(0));
    }

    function test_VaultEncoder_TransferOwnership_AsOwner() public {
        vm.prank(address(createdDao));
        VaultDepositPayoutActionEncoder encoder = VaultDepositPayoutActionEncoder(
            address(capitalDistributorPlugin.deployActionEncoder(toBytes32("vault-encoder"), ""))
        );

        address initialOwner = encoder.owner();

        vm.prank(initialOwner);
        encoder.transferOwnership(bob);

        assertEq(encoder.owner(), bob);
    }

    function test_VaultEncoder_TransferOwnership_AsDao() public {
        vm.startPrank(address(createdDao));
        VaultDepositPayoutActionEncoder encoder = VaultDepositPayoutActionEncoder(
            address(capitalDistributorPlugin.deployActionEncoder(toBytes32("vault-encoder"), ""))
        );
        vm.stopPrank();

        // DAO can transfer ownership
        vm.prank(address(createdDao));
        encoder.transferOwnership(carol);

        assertEq(encoder.owner(), carol);
    }

    // =========================================================================
    // Edge Cases and Complex Scenarios
    // =========================================================================

    function test_OwnershipTransferAndPermission() public {
        // Test that new owner can operate after ownership transfer
        vm.prank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);

        // Transfer ownership to alice
        vm.prank(strategy.owner());
        strategy.transferOwnership(alice);

        // Alice as new owner can set allocation
        bytes32 merkleRoot = keccak256("alice-merkle-root");
        vm.prank(alice);
        strategy.setAllocationCampaign(10, abi.encode(merkleRoot));

        assertEq(strategy.getCampaignMerkleRoot(10), merkleRoot);
    }

    function test_DaoCanOperateAfterOwnershipRenounced() public {
        // Test that DAO can still operate after ownership is renounced
        vm.startPrank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);
        vm.stopPrank();

        // Renounce ownership
        vm.prank(strategy.owner());
        strategy.renounceOwnership();

        // DAO can still operate even though there's no owner
        bytes32 merkleRoot = keccak256("dao-merkle-root");
        vm.prank(address(createdDao));
        strategy.setAllocationCampaign(20, abi.encode(merkleRoot));

        assertEq(strategy.getCampaignMerkleRoot(20), merkleRoot);
        assertEq(strategy.owner(), address(0));
    }

    function test_OnlyOwnerOrDaoCanOperate() public {
        // Test that only owner or DAO can operate, not other users
        vm.startPrank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);
        vm.stopPrank();

        // Owner can operate
        bytes32 merkleRoot1 = keccak256("owner-can-operate");
        vm.prank(strategy.owner());
        strategy.setAllocationCampaign(30, abi.encode(merkleRoot1));
        assertEq(strategy.getCampaignMerkleRoot(30), merkleRoot1);

        // DAO can operate
        bytes32 merkleRoot2 = keccak256("dao-can-operate");
        vm.prank(address(createdDao));
        strategy.setAllocationCampaign(31, abi.encode(merkleRoot2));
        assertEq(strategy.getCampaignMerkleRoot(31), merkleRoot2);

        // Regular users cannot operate
        bytes32 merkleRoot3 = keccak256("alice-cannot-operate");
        vm.expectRevert(abi.encodeWithSelector(IAllocatorStrategy.NotAuthorized.selector, alice));
        vm.prank(alice);
        strategy.setAllocationCampaign(32, abi.encode(merkleRoot3));
    }

    function test_OwnerTransferAndDaoAccess() public {
        // Test owner transfer and DAO access remain independent
        vm.startPrank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);
        vm.stopPrank();

        // Initial owner and DAO can both operate
        address initialOwner = strategy.owner();

        vm.prank(initialOwner);
        strategy.setAllocationCampaign(40, abi.encode(keccak256("initial-owner-root")));

        vm.prank(address(createdDao));
        strategy.setAllocationCampaign(41, abi.encode(keccak256("dao-root-1")));

        // Transfer ownership to alice
        vm.prank(initialOwner);
        strategy.transferOwnership(alice);

        // New owner (Alice) can operate
        vm.prank(alice);
        strategy.setAllocationCampaign(42, abi.encode(keccak256("alice-as-owner-root")));

        // DAO can still operate after ownership transfer
        vm.prank(address(createdDao));
        strategy.setAllocationCampaign(43, abi.encode(keccak256("dao-root-2")));

        // Initial owner can no longer operate
        vm.expectRevert(abi.encodeWithSelector(IAllocatorStrategy.NotAuthorized.selector, initialOwner));
        vm.prank(initialOwner);
        strategy.setAllocationCampaign(44, abi.encode(keccak256("should-fail")));
    }
}
