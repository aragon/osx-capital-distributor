// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { IAllocatorStrategy } from "../interfaces/IAllocatorStrategy.sol";
import { AllocatorStrategyBase } from "./AllocatorStrategyBase.sol";
import { CapitalDistributorPlugin } from "../CapitalDistributorPlugin.sol";

/// @title MerkleDistributorStrategy
/// @notice A merkle tree-based allocation strategy that allows recipients to claim tokens
/// by providing valid merkle proofs of their inclusion in the distribution.
/// @dev This strategy stores merkle roots for each campaign and verifies proofs on-chain.
/// The merkle tree leaves should be keccak256(abi.encodePacked(account, amount)).
contract MerkleDistributorStrategy is AllocatorStrategyBase {
    /// @notice Stores merkle root for each campaign
    struct MerkleCampaign {
        bytes32 merkleRoot;
    }

    /// @notice Maps campaign ID to merkle campaign data
    mapping(uint256 campaignId => MerkleCampaign) public merkleCampaigns;

    /// @notice Emitted when a new merkle campaign is set up
    event MerkleCampaignSet(uint256 indexed campaignId, bytes32 merkleRoot);

    /// @notice Emitted when a merkle campaign root is updated
    event MerkleCampaignUpdated(uint256 indexed campaignId, bytes32 oldMerkleRoot, bytes32 newMerkleRoot);

    /// @notice Thrown when trying to set a campaign that already exists
    error MerkleCampaignAlreadyExists(uint256 campaignId);

    /// @notice Thrown when the merkle root is zero (invalid)
    error InvalidMerkleRoot();

    /// @notice Thrown when the new merkle root is identical to the current one
    error DuplicateMerkleRoot(bytes32 root);

    /// @notice Thrown when the merkle proof verification fails
    error InvalidMerkleProof(uint256 campaignId, address account);

    /// @notice Thrown when no campaign exists for the given campaign ID
    error CampaignNotFound(uint256 campaignId);

    /// @notice Thrown when trying to update a campaign that is not active
    error CampaignNotPaused(uint256 campaignId);

    // =========================================================================
    // Public Encoder/Decoder Functions
    // =========================================================================

    /// @notice Encodes the initialization parameters for this strategy
    /// @dev This strategy doesn't use initialization parameters
    /// @return Empty bytes as no initialization data is needed
    function encodeInitializationParams() external pure returns (bytes memory) {
        return "";
    }

    /// @notice Encodes the parameters for setting up an allocation campaign
    /// @param _merkleRoot The merkle root for the campaign
    /// @return The encoded parameters
    function encodeSetAllocationCampaignParams(bytes32 _merkleRoot) external pure returns (bytes memory) {
        return abi.encode(_merkleRoot);
    }

    /// @notice Decodes the parameters for setting up an allocation campaign
    /// @param _data The encoded parameters
    /// @return merkleRoot The merkle root for the campaign
    function decodeSetAllocationCampaignParams(bytes memory _data) public pure returns (bytes32 merkleRoot) {
        return abi.decode(_data, (bytes32));
    }

    /// @notice Encodes the claim parameters for verifying an allocation
    /// @param _merkleProof The merkle proof for the claim
    /// @param _amount The claimable amount
    /// @return The encoded parameters
    function encodeClaimParams(bytes32[] memory _merkleProof, uint256 _amount) external pure returns (bytes memory) {
        return abi.encode(_merkleProof, _amount);
    }

    /// @notice Decodes the claim parameters for verifying an allocation
    /// @param _data The encoded parameters
    /// @return merkleProof The merkle proof for the claim
    /// @return amount The claimable amount
    function decodeClaimParams(bytes memory _data) public pure returns (bytes32[] memory merkleProof, uint256 amount) {
        return abi.decode(_data, (bytes32[], uint256));
    }

    /// @inheritdoc IAllocatorStrategy
    function setAllocationCampaign(uint256 _campaignId, bytes calldata _auxData) public override {
        if (msg.sender != owner()) {
            revert OnlyDAOAllowed(msg.sender);
        }

        // Check if campaign already exists
        if (merkleCampaigns[_campaignId].merkleRoot != bytes32(0)) {
            revert MerkleCampaignAlreadyExists(_campaignId);
        }

        bytes32 merkleRoot = decodeSetAllocationCampaignParams(_auxData);

        if (merkleRoot == bytes32(0)) {
            revert InvalidMerkleRoot();
        }

        // Initialize the campaign struct
        merkleCampaigns[_campaignId].merkleRoot = merkleRoot;

        emit AllocationCampaignCreated(plugin, _campaignId);
        emit MerkleCampaignSet(_campaignId, merkleRoot);
    }

    /// @inheritdoc IAllocatorStrategy
    function getTotalClaimableAmount(
        uint256 _campaignId,
        address _account,
        bytes calldata _auxData
    )
        public
        view
        override
        returns (uint256 amount)
    {
        bytes32 merkleRoot = merkleCampaigns[_campaignId].merkleRoot;

        if (merkleRoot == bytes32(0)) {
            return 0; // Campaign doesn't exist
        }

        (bytes32[] memory merkleProof, uint256 claimAmount) = decodeClaimParams(_auxData);

        // Create the leaf node: keccak256(abi.encodePacked(account, amount))
        bytes32 leaf = keccak256(abi.encodePacked(_account, claimAmount));

        // Verify the merkle proof
        if (!MerkleProof.verify(merkleProof, merkleRoot, leaf)) {
            return 0; // Invalid proof
        }

        return claimAmount;
    }

    /// @notice Gets the merkle root for a specific campaign
    /// @param _campaignId The campaign ID
    /// @return merkleRoot The merkle root for the campaign
    function getCampaignMerkleRoot(uint256 _campaignId) external view returns (bytes32 merkleRoot) {
        return merkleCampaigns[_campaignId].merkleRoot;
    }

    /// @notice Updates the merkle root for an existing campaign
    /// @param _campaignId The campaign ID to update
    /// @param _auxData The encoded data containing the new merkle root
    function updateCampaignMerkleRoot(uint256 _campaignId, bytes calldata _auxData) external {
        if (msg.sender != address(dao())) {
            revert OnlyDAOAllowed(msg.sender);
        }

        // Check if campaign is paused (not active, or ended)
        // The reason for this is so it's safe to take snapshots
        if (!CapitalDistributorPlugin(plugin).isCampaignPaused(_campaignId)) {
            revert CampaignNotPaused(_campaignId);
        }

        // Check if campaign exists
        bytes32 oldMerkleRoot = merkleCampaigns[_campaignId].merkleRoot;
        if (oldMerkleRoot == bytes32(0)) {
            revert CampaignNotFound(_campaignId);
        }

        bytes32 newMerkleRoot = decodeSetAllocationCampaignParams(_auxData);

        if (newMerkleRoot == bytes32(0)) {
            revert InvalidMerkleRoot();
        }

        // Prevent setting the same root again (no-op protection)
        if (newMerkleRoot == oldMerkleRoot) {
            revert DuplicateMerkleRoot(newMerkleRoot);
        }

        // Update the merkle root
        merkleCampaigns[_campaignId].merkleRoot = newMerkleRoot;

        emit MerkleCampaignUpdated(_campaignId, oldMerkleRoot, newMerkleRoot);
    }
}
