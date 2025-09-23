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
import { DaoUnauthorized } from "@aragon/commons/permission/auth/auth.sol";
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { IPluginRepo } from "@aragon/osx/framework/plugin/repo/IPluginRepo.sol";

contract AuthOrOwnerTest is AragonTest {
    MintableERC20 token;
    CapitalDistributorPlugin capitalDistributorPlugin;
    
    address testAlice = makeAddr("testAlice");
    address testBob = makeAddr("testBob");
    address charlie = makeAddr("charlie");

    bytes32 constant STRATEGY_MANAGER_PERMISSION_ID = keccak256("STRATEGY_MANAGER_PERMISSION");
    bytes32 constant ENCODER_MANAGER_PERMISSION_ID = keccak256("ENCODER_MANAGER_PERMISSION");
    bytes32 constant CAMPAIGN_MANAGER_PERMISSION_ID = keccak256("CAMPAIGN_MANAGER_PERMISSION");

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
            toBytes32("vault-encoder"),
            address(new VaultDepositPayoutActionEncoder()),
            "Vault Deposit Payout Encoder"
        );
        
        vm.stopPrank();
    }

    // =========================================================================
    // MerkleDistributorStrategy authOrOwner Tests
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

    function test_MerkleStrategy_SetAllocationCampaign_WithPermission() public {
        // Deploy strategy
        vm.prank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);
        
        // Grant permission to testAlice
        vm.prank(address(createdDao));
        createdDao.grant(address(strategy), testAlice, STRATEGY_MANAGER_PERMISSION_ID);
        
        // Alice should be able to call setAllocationCampaign
        bytes32 merkleRoot = keccak256("test-merkle-root");
        
        vm.prank(testAlice);
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
        
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, 
                createdDao, 
                address(strategy), 
                testBob, 
                STRATEGY_MANAGER_PERMISSION_ID
            )
        );
        vm.prank(testBob);
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
                toBytes32("merkle-strategy"), 
                "", 
                abi.encode(keccak256("initial-root"))
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

    function test_MerkleStrategy_UpdateMerkleRoot_WithPermission() public {
        // Setup campaign
        vm.startPrank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);
        
        token.mint(address(createdDao), 10 ether);
        
        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://metadata",
            CapitalDistributorPlugin.StrategyConfig(
                toBytes32("merkle-strategy"), 
                "", 
                abi.encode(keccak256("initial-root"))
            ),
            CapitalDistributorPlugin.PayoutConfig(token, bytes32(0), ""),
            CapitalDistributorPlugin.CampaignSettings(0, 0)
        );
        
        capitalDistributorPlugin.pauseCampaign(campaignId);
        
        // Grant permission to charlie
        createdDao.grant(address(strategy), charlie, STRATEGY_MANAGER_PERMISSION_ID);
        vm.stopPrank();
        
        // Charlie updates merkle root
        bytes32 newRoot = keccak256("charlie-new-root");
        vm.prank(charlie);
        strategy.updateCampaignMerkleRoot(campaignId, abi.encode(newRoot));
        
        assertEq(strategy.getCampaignMerkleRoot(campaignId), newRoot);
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

    function test_MerkleStrategy_RenounceOwnership_WithPermission() public {
        vm.startPrank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);
        
        // Grant permission to testAlice
        createdDao.grant(address(strategy), testAlice, STRATEGY_MANAGER_PERMISSION_ID);
        vm.stopPrank();
        
        // Now with the fix, testAlice can renounce ownership with permission
        vm.prank(testAlice);
        strategy.renounceOwnership();
        
        assertEq(strategy.owner(), address(0));
    }

    function test_MerkleStrategy_TransferOwnership_AsOwner() public {
        vm.prank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);
        
        address initialOwner = strategy.owner();
        
        vm.prank(initialOwner);
        strategy.transferOwnership(testBob);
        
        assertEq(strategy.owner(), testBob);
    }

    function test_MerkleStrategy_TransferOwnership_WithPermission() public {
        vm.startPrank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);
        
        // Grant permission to testAlice
        createdDao.grant(address(strategy), testAlice, STRATEGY_MANAGER_PERMISSION_ID);
        vm.stopPrank();
        
        // Now with the fix, testAlice can transfer ownership with permission
        vm.prank(testAlice);
        strategy.transferOwnership(charlie);
        
        assertEq(strategy.owner(), charlie);
    }

    // =========================================================================
    // VaultDepositPayoutActionEncoder authOrOwner Tests  
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

    function test_VaultEncoder_SetupCampaign_WithPermission() public {
        vm.startPrank(address(createdDao));
        VaultDepositPayoutActionEncoder encoder = VaultDepositPayoutActionEncoder(
            address(capitalDistributorPlugin.deployActionEncoder(toBytes32("vault-encoder"), ""))
        );
        
        // Grant permission to testAlice
        createdDao.grant(address(encoder), testAlice, ENCODER_MANAGER_PERMISSION_ID);
        vm.stopPrank();
        
        address vault = makeAddr("vault");
        
        vm.prank(testAlice);
        encoder.setupCampaign(2, abi.encode(vault));
        
        assertEq(encoder.campaignVaults(2), vault);
    }

    function test_VaultEncoder_SetupCampaign_RevertUnauthorized() public {
        vm.prank(address(createdDao));
        VaultDepositPayoutActionEncoder encoder = VaultDepositPayoutActionEncoder(
            address(capitalDistributorPlugin.deployActionEncoder(toBytes32("vault-encoder"), ""))
        );
        
        address vault = makeAddr("vault");
        
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                createdDao,
                address(encoder),
                testBob,
                ENCODER_MANAGER_PERMISSION_ID
            )
        );
        vm.prank(testBob);
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

    function test_VaultEncoder_RenounceOwnership_WithPermission() public {
        vm.startPrank(address(createdDao));
        VaultDepositPayoutActionEncoder encoder = VaultDepositPayoutActionEncoder(
            address(capitalDistributorPlugin.deployActionEncoder(toBytes32("vault-encoder"), ""))
        );
        
        // Grant permission to testAlice
        createdDao.grant(address(encoder), testAlice, ENCODER_MANAGER_PERMISSION_ID);
        vm.stopPrank();
        
        // Now with the fix, testAlice can renounce ownership with permission
        vm.prank(testAlice);
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
        encoder.transferOwnership(testBob);
        
        assertEq(encoder.owner(), testBob);
    }

    function test_VaultEncoder_TransferOwnership_WithPermission() public {
        vm.startPrank(address(createdDao));
        VaultDepositPayoutActionEncoder encoder = VaultDepositPayoutActionEncoder(
            address(capitalDistributorPlugin.deployActionEncoder(toBytes32("vault-encoder"), ""))
        );
        
        // Grant permission to testAlice
        createdDao.grant(address(encoder), testAlice, ENCODER_MANAGER_PERMISSION_ID);
        vm.stopPrank();
        
        // Now with the fix, testAlice can transfer ownership with permission
        vm.prank(testAlice);
        encoder.transferOwnership(charlie);
        
        assertEq(encoder.owner(), charlie);
    }

    // =========================================================================
    // Edge Cases and Complex Scenarios
    // =========================================================================

    function test_OwnershipTransferAndPermission() public {
        // Test that new owner can operate after ownership transfer
        vm.prank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);
        
        // Transfer ownership to testAlice
        vm.prank(strategy.owner());
        strategy.transferOwnership(testAlice);
        
        // Alice as new owner can set allocation
        bytes32 merkleRoot = keccak256("testAlice-merkle-root");
        vm.prank(testAlice);
        strategy.setAllocationCampaign(10, abi.encode(merkleRoot));
        
        assertEq(strategy.getCampaignMerkleRoot(10), merkleRoot);
    }

    function test_PermissionAfterOwnershipRenounced() public {
        // Test that permission still works after ownership is renounced
        vm.startPrank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);
        
        // Grant permission to testBob before renouncing
        createdDao.grant(address(strategy), testBob, STRATEGY_MANAGER_PERMISSION_ID);
        vm.stopPrank();
        
        // Renounce ownership
        vm.prank(strategy.owner());
        strategy.renounceOwnership();
        
        // Bob can still operate with permission even though there's no owner
        bytes32 merkleRoot = keccak256("testBob-merkle-root");
        vm.prank(testBob);
        strategy.setAllocationCampaign(20, abi.encode(merkleRoot));
        
        assertEq(strategy.getCampaignMerkleRoot(20), merkleRoot);
        assertEq(strategy.owner(), address(0));
    }

    function test_RevokePermissionAfterGrant() public {
        // Test revoking permissions
        vm.startPrank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);
        
        // Grant permission to testAlice
        createdDao.grant(address(strategy), testAlice, STRATEGY_MANAGER_PERMISSION_ID);
        
        // Alice can operate
        bytes32 merkleRoot1 = keccak256("testAlice-can-operate");
        vm.startPrank(testAlice);
        strategy.setAllocationCampaign(30, abi.encode(merkleRoot1));
        vm.stopPrank();
        
        // Revoke permission
        vm.prank(address(createdDao));
        createdDao.revoke(address(strategy), testAlice, STRATEGY_MANAGER_PERMISSION_ID);
        
        // Alice cannot operate anymore
        bytes32 merkleRoot2 = keccak256("testAlice-cannot-operate");
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                createdDao,
                address(strategy),
                testAlice,
                STRATEGY_MANAGER_PERMISSION_ID
            )
        );
        vm.prank(testAlice);
        strategy.setAllocationCampaign(31, abi.encode(merkleRoot2));
    }

    function test_MultipleUsersWithPermission() public {
        // Test multiple users with same permission
        vm.startPrank(address(createdDao));
        address strategyAddr = capitalDistributorPlugin.deployStrategy(toBytes32("merkle-strategy"), "");
        MerkleDistributorStrategy strategy = MerkleDistributorStrategy(strategyAddr);
        
        // Grant permission to both testAlice and testBob
        createdDao.grant(address(strategy), testAlice, STRATEGY_MANAGER_PERMISSION_ID);
        createdDao.grant(address(strategy), testBob, STRATEGY_MANAGER_PERMISSION_ID);
        vm.stopPrank();
        
        // Both can operate
        vm.prank(testAlice);
        strategy.setAllocationCampaign(40, abi.encode(keccak256("testAlice-root")));
        
        vm.prank(testBob);
        strategy.setAllocationCampaign(41, abi.encode(keccak256("testBob-root")));
        
        assertEq(strategy.getCampaignMerkleRoot(40), keccak256("testAlice-root"));
        assertEq(strategy.getCampaignMerkleRoot(41), keccak256("testBob-root"));
    }

}