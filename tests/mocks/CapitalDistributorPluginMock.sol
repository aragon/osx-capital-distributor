// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { ICapitalDistributorPlugin } from "../../src/interfaces/ICapitalDistributorPlugin.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IAllocatorStrategy } from "../../src/interfaces/IAllocatorStrategy.sol";
import { IPayoutActionEncoder } from "../../src/interfaces/IPayoutActionEncoder.sol";

/// @title CapitalDistributorPluginMock
/// @notice Mock implementation of ICapitalDistributorPlugin for testing factory authorization
contract CapitalDistributorPluginMock is ICapitalDistributorPlugin {
    function CAMPAIGN_MANAGER_PERMISSION_ID() external pure returns (bytes32) {
        return keccak256("CAMPAIGN_MANAGER_PERMISSION");
    }

    function numCampaigns() external pure returns (uint256) {
        return 0;
    }

    function isCampaignActive(uint256) external pure returns (bool) {
        return false;
    }

    function isCampaignPaused(uint256) external pure returns (bool) {
        return false;
    }

    function getCampaign(uint256) external pure returns (Campaign memory campaign) {
        return Campaign({
            metadataUri: "",
            allocationStrategy: IAllocatorStrategy(address(0)),
            token: IERC20(address(0)),
            actionEncoder: IPayoutActionEncoder(address(0)),
            state: CampaignState.ACTIVE,
            startTime: 0,
            endTime: 0
        });
    }

    function getCampaignStrategyId(uint256) external pure returns (bytes32) {
        return bytes32(0);
    }

    function getCampaignEncoderId(uint256) external pure returns (bytes32) {
        return bytes32(0);
    }

    function getClaimedAmount(uint256, address) external pure returns (uint256) {
        return 0;
    }

    function getStrategyInitializationEncodingTypes(bytes32) external pure returns (string memory) {
        return "";
    }

    function getStrategyCreationEncodingTypes(uint256) external pure returns (string memory) {
        return "";
    }

    function getStrategyClaimEncodingTypes(uint256) external pure returns (string memory) {
        return "";
    }

    function getEncoderCreationEncodingTypes(uint256) external pure returns (string memory) {
        return "";
    }

    function getEncoderClaimEncodingTypes(uint256) external pure returns (string memory) {
        return "";
    }

    // ====================================
    // Core Campaign Management Functions
    // ====================================

    function createCampaign(
        bytes calldata,
        StrategyConfig calldata,
        PayoutConfig calldata,
        CampaignSettings calldata
    )
        external
        pure
        returns (uint256)
    {
        return 0;
    }

    function claimCampaignPayout(uint256, address, bytes calldata, bytes calldata) external pure returns (uint256) {
        return 0;
    }

    function claimCampaignPayoutToAddress(
        uint256,
        address,
        bytes calldata,
        bytes calldata
    )
        external
        pure
        returns (uint256)
    {
        return 0;
    }

    function batchClaimCampaignPayout(
        uint256[] calldata,
        address[] calldata,
        bytes[] calldata,
        bytes[] calldata
    )
        external
        pure
        returns (uint256[] memory)
    {
        return new uint256[](0);
    }

    // ====================================
    // Campaign State Management Functions
    // ====================================

    function pauseCampaign(uint256) external pure {
        // Mock implementation
    }

    function resumeCampaign(uint256) external pure {
        // Mock implementation
    }

    function endCampaign(uint256) external pure {
        // Mock implementation
    }

    // ====================================
    // Factory Integration Functions
    // ====================================

    function deployStrategy(bytes32, bytes calldata) external pure returns (address) {
        return address(0);
    }

    function deployActionEncoder(bytes32, bytes calldata) external pure returns (address) {
        return address(0);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ICapitalDistributorPlugin).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
