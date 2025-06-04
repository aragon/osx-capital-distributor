// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {console2} from "forge-std/console2.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IAllocatorStrategy} from "../interfaces/IAllocatorStrategy.sol";
import {AllocatorStrategyBase} from "./AllocatorStrategyBase.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";

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

    /// @notice Maps plugin address to campaign ID to merkle campaign data
    mapping(address plugin => mapping(uint256 campaignId => MerkleCampaign)) public merkleCampaigns;

    /// @notice Emitted when a new merkle campaign is set up
    event MerkleCampaignSet(address indexed plugin, uint256 indexed campaignId, bytes32 merkleRoot);

    /// @notice Emitted when a recipient claims their allocation
    event AllocationClaimed(
        address indexed plugin,
        uint256 indexed campaignId,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Emitted when a merkle campaign root is updated
    event MerkleCampaignUpdated(
        address indexed plugin,
        uint256 indexed campaignId,
        bytes32 oldMerkleRoot,
        bytes32 newMerkleRoot
    );

    /// @notice Thrown when trying to set a campaign that already exists
    error MerkleCampaignAlreadyExists(address plugin, uint256 campaignId);

    /// @notice Thrown when the merkle root is zero (invalid)
    error InvalidMerkleRoot();

    /// @notice Thrown when the merkle proof verification fails
    error InvalidMerkleProof(address plugin, uint256 campaignId, address account);

    /// @notice Thrown when a recipient has already claimed their allocation
    error AlreadyClaimed(address plugin, uint256 campaignId, address account);

    /// @notice Thrown when no campaign exists for the given plugin and campaign ID
    error CampaignNotFound(address plugin, uint256 campaignId);

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
    function setAllocationCampaign(uint256 _campaignId, bytes calldata _auxData) public override {
        address plugin = msg.sender;

        // Check if campaign already exists
        if (merkleCampaigns[plugin][_campaignId].merkleRoot != bytes32(0)) {
            revert MerkleCampaignAlreadyExists(plugin, _campaignId);
        }

        bytes32 merkleRoot = decodeCampaignSetupData(_auxData);

        if (merkleRoot == bytes32(0)) {
            revert InvalidMerkleRoot();
        }

        // Initialize the campaign struct (merkleRoot is set, hasClaimed mapping is automatically empty)
        merkleCampaigns[plugin][_campaignId].merkleRoot = merkleRoot;

        emit MerkleCampaignSet(plugin, _campaignId, merkleRoot);
    }

    /// @inheritdoc IAllocatorStrategy
    function getClaimeableAmount(
        uint256 _campaignId,
        address _account,
        bytes calldata _auxData
    ) public view override returns (uint256 amount) {
        address plugin = msg.sender;
        bytes32 merkleRoot = merkleCampaigns[plugin][_campaignId].merkleRoot;

        if (merkleRoot == bytes32(0)) {
            return 0; // Campaign doesn't exist
        }

        (bytes32[] memory merkleProof, uint256 claimAmount) = decodeClaimData(_auxData);

        // Check if already claimed
        if (merkleCampaigns[plugin][_campaignId].claimed[_account] >= claimAmount) {
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

    /// @notice Checks if an account has already claimed for a specific campaign
    /// @param _plugin The plugin address that created the campaign
    /// @param _campaignId The campaign ID
    /// @param _account The account to check
    /// @return claimed True if the account has already claimed, false otherwise
    function hasClaimed(address _plugin, uint256 _campaignId, address _account) external view returns (bool claimed) {
        return merkleCampaigns[_plugin][_campaignId].claimed[_account] > 0;
    }

    /// @notice Gets the merkle root for a specific campaign
    /// @param _plugin The plugin address that created the campaign
    /// @param _campaignId The campaign ID
    /// @return merkleRoot The merkle root for the campaign
    function getCampaignMerkleRoot(address _plugin, uint256 _campaignId) external view returns (bytes32 merkleRoot) {
        return merkleCampaigns[_plugin][_campaignId].merkleRoot;
    }

    /// @notice Updates the merkle root for an existing campaign
    /// @param _campaignId The campaign ID to update
    /// @param _auxData The encoded data containing the new merkle root
    function updateCampaignMerkleRoot(uint256 _campaignId, bytes calldata _auxData) external {
        address plugin = msg.sender;

        // Check if campaign exists
        bytes32 oldMerkleRoot = merkleCampaigns[plugin][_campaignId].merkleRoot;
        if (oldMerkleRoot == bytes32(0)) {
            revert CampaignNotFound(plugin, _campaignId);
        }

        bytes32 newMerkleRoot = decodeCampaignSetupData(_auxData);

        if (newMerkleRoot == bytes32(0)) {
            revert InvalidMerkleRoot();
        }

        // Update the merkle root
        merkleCampaigns[plugin][_campaignId].merkleRoot = newMerkleRoot;

        emit MerkleCampaignUpdated(plugin, _campaignId, oldMerkleRoot, newMerkleRoot);
    }
}
