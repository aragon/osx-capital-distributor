// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {IPayoutActionEncoder} from "../src/interfaces/IPayoutActionEncoder.sol";
import {CapitalDistributorPlugin} from "../src/CapitalDistributorPlugin.sol";
import {AragonTest} from "./helpers/AragonTest.sol";
import {IAllocatorStrategy} from "../src/interfaces/IAllocatorStrategy.sol";
import {IAllocatorStrategyFactory} from "../src/interfaces/IAllocatorStrategyFactory.sol";
import {MerkleDistributorStrategy} from "../src/allocatorStrategies/MerkleDistributorStrategy.sol";

import {MintableERC20} from "./mocks/MintableERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract MerkleDistributorStrategyTest is AragonTest {
    CapitalDistributorPlugin capitalDistributorPlugin;
    MerkleDistributorStrategy strategy;
    MintableERC20 token;

    // Merkle tree test data
    address[] recipients;
    uint256[] amounts;
    bytes32[] leaves;
    bytes32 merkleRoot;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        // Instantiate the contract-under-test.
        capitalDistributorPlugin = CapitalDistributorPlugin(pluginAddress[0]);
        token = new MintableERC20();
        strategy = new MerkleDistributorStrategy();

        vm.startPrank(address(createdDAO));
        allocatorStrategyFactory.registerStrategyType(toBytes32("merkle-strategy"), address(strategy), "");

        // Set up merkle tree test data
        setupMerkleTreeData();
    }

    function setupMerkleTreeData() internal {
        // Create test recipients and amounts
        recipients = new address[](4);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = carol;
        recipients[3] = david;

        amounts = new uint256[](4);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;
        amounts[3] = 4 ether;

        // Create leaves for merkle tree
        leaves = new bytes32[](4);
        for (uint256 i = 0; i < recipients.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(recipients[i], amounts[i]));
        }

        // Calculate merkle root using proper OpenZeppelin-compatible construction
        // Level 1: pair adjacent leaves with sorted hashing
        bytes32 level1_0 = _hashPair(leaves[0], leaves[1]);
        bytes32 level1_1 = _hashPair(leaves[2], leaves[3]);

        // Level 2 (root): hash the two level 1 nodes
        merkleRoot = _hashPair(level1_0, level1_1);
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function getMerkleProof(uint256 index) internal view returns (bytes32[] memory proof) {
        proof = new bytes32[](2);

        if (index == 0) {
            // Alice's proof
            proof[0] = leaves[1]; // Bob's leaf (sibling at level 0)
            proof[1] = _hashPair(leaves[2], leaves[3]); // Carol + David hash (uncle at level 1)
        } else if (index == 1) {
            // Bob's proof
            proof[0] = leaves[0]; // Alice's leaf (sibling at level 0)
            proof[1] = _hashPair(leaves[2], leaves[3]); // Carol + David hash (uncle at level 1)
        } else if (index == 2) {
            // Carol's proof
            proof[0] = leaves[3]; // David's leaf (sibling at level 0)
            proof[1] = _hashPair(leaves[0], leaves[1]); // Alice + Bob hash (uncle at level 1)
        } else if (index == 3) {
            // David's proof
            proof[0] = leaves[2]; // Carol's leaf (sibling at level 0)
            proof[1] = _hashPair(leaves[0], leaves[1]); // Alice + Bob hash (uncle at level 1)
        }
    }

    function test_CreateCampaign() public {
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        IAllocatorStrategyFactory.DeploymentParams memory allocatorDeploymentParams = IAllocatorStrategyFactory
            .DeploymentParams({epochDuration: 1 days, claimOpen: true, auxData: ""});

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(merkleRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        assertEq(campaign.metadataURI, metadata, "Metadata not equal");
        assertTrue(address(campaign.allocationStrategy) != address(0), "Allocation strategy not set");
    }

    function test_CannotCreateCampaignWithoutPermissions() public {
        vm.startPrank(address(alice));
        bytes memory metadata = "";
        IAllocatorStrategyFactory.DeploymentParams memory allocatorDeploymentParams = IAllocatorStrategyFactory
            .DeploymentParams({epochDuration: 1 days, claimOpen: true, auxData: ""});

        vm.expectRevert();
        capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(merkleRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false
        );
    }

    function test_PayoutIsSent() public {
        token.mint(address(createdDAO), 10 ether);
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        IAllocatorStrategyFactory.DeploymentParams memory allocatorDeploymentParams = IAllocatorStrategyFactory
            .DeploymentParams({epochDuration: 1 days, claimOpen: true, auxData: ""});

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(merkleRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false
        );
        vm.stopPrank();

        // Test Alice's claim
        bytes32[] memory aliceProof = getMerkleProof(0);
        bytes memory claimAuxData = abi.encode(aliceProof, amounts[0]);

        assertEq(token.balanceOf(address(createdDAO)), 10 ether, "DAO doesn't have funds");
        assertEq(token.balanceOf(alice), 0 ether, "Alice has funds before claim");

        vm.startPrank(address(createdDAO));
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, claimAuxData);

        assertEq(token.balanceOf(address(createdDAO)), 9 ether, "DAO should have 9 ether left");
        assertEq(token.balanceOf(alice), 1 ether, "Alice should have 1 ether");
    }

    function test_MultipleRecipientsClaim() public {
        token.mint(address(createdDAO), 10 ether);
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        IAllocatorStrategyFactory.DeploymentParams memory allocatorDeploymentParams = IAllocatorStrategyFactory
            .DeploymentParams({epochDuration: 1 days, claimOpen: true, auxData: ""});

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(merkleRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false
        );
        vm.stopPrank();

        vm.startPrank(address(capitalDistributorPlugin));

        // Alice claims
        bytes32[] memory aliceProof = getMerkleProof(0);
        bytes memory aliceClaimData = abi.encode(aliceProof, amounts[0]);
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, aliceClaimData);

        // Bob claims
        bytes32[] memory bobProof = getMerkleProof(1);
        bytes memory bobClaimData = abi.encode(bobProof, amounts[1]);
        capitalDistributorPlugin.claimCampaignPayout(campaignId, bob, bobClaimData);

        assertEq(token.balanceOf(alice), 1 ether, "Alice should have 1 ether");
        assertEq(token.balanceOf(bob), 2 ether, "Bob should have 2 ether");
        assertEq(token.balanceOf(address(createdDAO)), 7 ether, "DAO should have 7 ether left");
    }

    function test_InvalidProofReverts() public {
        token.mint(address(createdDAO), 10 ether);
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        IAllocatorStrategyFactory.DeploymentParams memory allocatorDeploymentParams = IAllocatorStrategyFactory
            .DeploymentParams({epochDuration: 1 days, claimOpen: true, auxData: ""});

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(merkleRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false
        );
        vm.stopPrank();

        // Create invalid proof (using Bob's proof for Alice)
        bytes32[] memory invalidProof = getMerkleProof(1);
        bytes memory invalidClaimData = abi.encode(invalidProof, amounts[0]);

        vm.startPrank(address(capitalDistributorPlugin));
        vm.expectRevert(abi.encodeWithSelector(CapitalDistributorPlugin.NoClaimableAmount.selector, campaignId, alice));
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, invalidClaimData);
    }

    function test_CannotClaimTwice() public {
        token.mint(address(createdDAO), 10 ether);
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        IAllocatorStrategyFactory.DeploymentParams memory allocatorDeploymentParams = IAllocatorStrategyFactory
            .DeploymentParams({epochDuration: 1 days, claimOpen: true, auxData: ""});

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(merkleRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false
        );
        vm.stopPrank();

        vm.startPrank(address(capitalDistributorPlugin));

        // Alice claims successfully
        bytes32[] memory aliceProof = getMerkleProof(0);
        bytes memory aliceClaimData = abi.encode(aliceProof, amounts[0]);
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, aliceClaimData);

        // Alice tries to claim again - should revert
        vm.expectRevert(
            abi.encodeWithSelector(CapitalDistributorPlugin.MultipleClaimsNotAllowed.selector, campaignId, alice)
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, aliceClaimData);
    }

    function test_GetCampaignPayout() public {
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        IAllocatorStrategyFactory.DeploymentParams memory allocatorDeploymentParams = IAllocatorStrategyFactory
            .DeploymentParams({epochDuration: 1 days, claimOpen: true, auxData: ""});

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("merkle-strategy"),
            allocatorDeploymentParams,
            abi.encode(merkleRoot),
            IERC20(token),
            bytes32(0),
            metadata,
            false
        );
        vm.stopPrank();

        // Check Alice's payout amount
        bytes32[] memory aliceProof = getMerkleProof(0);
        bytes memory aliceClaimData = abi.encode(aliceProof, amounts[0]);

        uint256 payoutAmount = capitalDistributorPlugin.getCampaignPayout(campaignId, alice, aliceClaimData);
        assertEq(payoutAmount, 1 ether, "Alice's payout should be 1 ether");

        // Check Bob's payout amount
        bytes32[] memory bobProof = getMerkleProof(1);
        bytes memory bobClaimData = abi.encode(bobProof, amounts[1]);

        payoutAmount = capitalDistributorPlugin.getCampaignPayout(campaignId, bob, bobClaimData);
        assertEq(payoutAmount, 2 ether, "Bob's payout should be 2 ether");
    }
}
