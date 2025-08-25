// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {console2} from "forge-std/console2.sol";

import {DaoAuthorizableUpgradeable} from "@aragon/commons/permission/auth/DaoAuthorizableUpgradeable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IAllocatorStrategy} from "../interfaces/IAllocatorStrategy.sol";
import {AllocatorStrategyBase} from "./AllocatorStrategyBase.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {CapitalDistributorPlugin} from "../CapitalDistributorPlugin.sol";

/// @title MerkleDistributorStrategy
/// @notice A merkle tree-based allocation strategy that allows recipients to claim tokens
/// by providing valid merkle proofs of their inclusion in the distribution.
/// @dev This strategy stores merkle roots for each campaign and verifies proofs on-chain.
/// The merkle tree leaves should be keccak256(abi.encodePacked(account, amount)).
contract MerkleDistributorStrategy is AllocatorStrategyBase {
    /// @notice Stores merkle root and metadata for each campaign
    struct MerkleCampaign {
        bytes32 merkleRoot;
        mapping(address => uint256) claimed;
    }

    /// @notice Maps campaign ID to merkle campaign data
    mapping(uint256 campaignId => MerkleCampaign) public merkleCampaigns;

    /// @notice Emitted when a new merkle campaign is set up
    event MerkleCampaignSet(uint256 indexed campaignId, bytes32 merkleRoot);

    /// @notice Emitted when a recipient claims their allocation
    event AllocationClaimed(
        uint256 indexed campaignId,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Emitted when a merkle campaign root is updated
    event MerkleCampaignUpdated(
        uint256 indexed campaignId,
        bytes32 oldMerkleRoot,
        bytes32 newMerkleRoot
    );

    /// @notice Thrown when trying to set a campaign that already exists
    error MerkleCampaignAlreadyExists(uint256 campaignId);

    /// @notice Thrown when the merkle root is zero (invalid)
    error InvalidMerkleRoot();

    /// @notice Thrown when the new merkle root is identical to the current one
    error DuplicateMerkleRoot(bytes32 root);

    /// @notice Thrown when the merkle proof verification fails
    error InvalidMerkleProof(uint256 campaignId, address account);

    /// @notice Thrown when a recipient has already claimed their allocation
    error AlreadyClaimed(uint256 campaignId, address account);

    /// @notice Thrown when no campaign exists for the given campaign ID
    error CampaignNotFound(uint256 campaignId);

    /// @notice Thrown when trying to update a campaign that is not active
    error CampaignNotActiveForUpdate(uint256 campaignId);

    /// @notice Decodes the auxiliary data for setting up a merkle campaign
    /// @param _auxData The encoded data containing the merkle root
    /// @return merkleRoot The merkle root for the campaign
    function decodeCampaignSetupData(bytes calldata _auxData) internal pure returns (bytes32 merkleRoot) {
        return abi.decode(_auxData, (bytes32));
    }

    /// @notice Decodes the auxiliary data for claiming an allocation
    /// @param _auxData The encoded data containing the merkle proof and claimed amount
    /// @return merkleProof The merkle proof for the claim
    /// @return amount The amount being claimed
    function decodeClaimData(
        bytes calldata _auxData
    ) internal pure returns (bytes32[] memory merkleProof, uint256 amount) {
        return abi.decode(_auxData, (bytes32[], uint256));
    }

    /// @inheritdoc IAllocatorStrategy
    function getInitializationEncodingTypes() external pure override returns (string memory types) {
        return ""; // This strategy doesn't use auxData for initialization
    }

    /// @inheritdoc IAllocatorStrategy
    function getCreationEncodingTypes() external pure override returns (string memory types) {
        return "bytes32"; // merkleRoot
    }

    /// @inheritdoc IAllocatorStrategy
    function getClaimEncodingTypes() external pure override returns (string memory types) {
        return "bytes32[],uint256"; // merkleProof, amount
    }

    /// @inheritdoc IAllocatorStrategy
    function setAllocationCampaign(uint256 _campaignId, bytes calldata _auxData) public override {
        if (msg.sender != owner() && msg.sender != address(dao())) {
            revert OnlyDAOAllowed(msg.sender);
        }

        // Check if campaign already exists
        if (merkleCampaigns[_campaignId].merkleRoot != bytes32(0)) {
            revert MerkleCampaignAlreadyExists(_campaignId);
        }

        bytes32 merkleRoot = decodeCampaignSetupData(_auxData);

        if (merkleRoot == bytes32(0)) {
            revert InvalidMerkleRoot();
        }

        // Initialize the campaign struct (merkleRoot is set, hasClaimed mapping is automatically empty)
        merkleCampaigns[_campaignId].merkleRoot = merkleRoot;

        emit AllocationCampaignCreated(plugin, _campaignId);
        emit MerkleCampaignSet(_campaignId, merkleRoot);
    }

    /// @inheritdoc IAllocatorStrategy
    function getClaimeableAmount(
        uint256 _campaignId,
        address _account,
        bytes calldata _auxData
    ) public view override returns (uint256 amount) {
        bytes32 merkleRoot = merkleCampaigns[_campaignId].merkleRoot;

        if (merkleRoot == bytes32(0)) {
            return 0; // Campaign doesn't exist
        }

        (bytes32[] memory merkleProof, uint256 claimAmount) = decodeClaimData(_auxData);

        // Check if already claimed
        if (merkleCampaigns[_campaignId].claimed[_account] >= claimAmount) {
            return 0; // Already claimed
        }

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
        if (msg.sender != owner() && msg.sender != address(dao())) {
            revert OnlyDAOAllowed(msg.sender);
        }

        // Check if campaign is active (not paused or ended)
        if (!CapitalDistributorPlugin(plugin).isCampaignActive(_campaignId)) {
            revert CampaignNotActiveForUpdate(_campaignId);
        }

        // Check if campaign exists
        bytes32 oldMerkleRoot = merkleCampaigns[_campaignId].merkleRoot;
        if (oldMerkleRoot == bytes32(0)) {
            revert CampaignNotFound(_campaignId);
        }

        bytes32 newMerkleRoot = decodeCampaignSetupData(_auxData);

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

    // =========================================================================
    // Storage Gap
    // =========================================================================
    
    /// @dev Storage gap to allow for future upgrades without storage collision.
    /// This contract adds 1 storage slot: merkleCampaigns mapping.
    uint256[49] private __gap;
}
