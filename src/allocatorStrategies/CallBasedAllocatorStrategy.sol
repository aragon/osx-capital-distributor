// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {IAllocatorStrategy} from "../interfaces/IAllocatorStrategy.sol";
import {AllocatorStrategyBase} from "./AllocatorStrategyBase.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {Action} from "@aragon/commons/executors/IExecutor.sol";

/// @title AllocatorStrategyMock
/// @notice A mock implementation of AllocatorStrategyBase for testing purposes.
/// @dev This mock provides basic implementations for abstract functions:
///      - `isEligible` always returns `true`.
///      - `getPayoutAmount` always returns `1 ether`.
///      It also ensures that internal functions are protected by Aragon OSx's DaoAuthorizable.
contract CallBasedAllocatorStrategy is AllocatorStrategyBase {
    struct ActionCall {
        address to;
        bytes4 functionSelector;
    }

    struct AllocationCampaign {
        ActionCall isEligibleAction;
        ActionCall getPayoutAmountAction;
    }

    mapping(address plugin => mapping(uint256 campaignId => AllocationCampaign)) allocationCampaigns;

    error AllocationCampaignAlreadyExists(address plugin, uint256 campaignId);
    error CallFailed(address plugin, uint256 campaignId, address account);

    constructor(
        IDAO _dao,
        uint256 _epochDuration,
        bool _claimOpen
    ) AllocatorStrategyBase(_dao, _epochDuration, _claimOpen) {}

    function decodeAllocationCampaignParams(
        bytes calldata _auxData
    ) internal pure returns (ActionCall memory isEligibleAction, ActionCall memory getPayoutAmountAction) {
        return abi.decode(_auxData, (ActionCall, ActionCall));
    }

    function setAllocationCampaign(uint256 _campaignId, bytes calldata _audData) public override {
        // TODO: Revert when the aux data doesn't fit
        // TODO: Ensure this call is being done by the plugin

        address _plugin = msg.sender;
        if (allocationCampaigns[_plugin][_campaignId].isEligibleAction.to != address(0)) {
            revert AllocationCampaignAlreadyExists(_plugin, _campaignId);
        }

        AllocationCampaign storage campaign = allocationCampaigns[_plugin][_campaignId];

        (
            ActionCall memory _isEligibleAction,
            ActionCall memory _getPayoutAmountAction
        ) = decodeAllocationCampaignParams(_audData);

        campaign.isEligibleAction = _isEligibleAction;
        campaign.getPayoutAmountAction = _getPayoutAmountAction;
    }

    function canClaim(uint256 _campaignId, address _account, bytes calldata) public view returns (bool eligible) {
        AllocationCampaign storage _allocationCampaign = allocationCampaigns[msg.sender][_campaignId];
        if (_allocationCampaign.getPayoutAmountAction.to == address(0)) return false;

        // Call if it's eligible
        if (_allocationCampaign.isEligibleAction.to == address(0)) return true;
        else {
            bytes memory callData = abi.encodeWithSelector(
                _allocationCampaign.isEligibleAction.functionSelector,
                _account
            );
            (bool success, bytes memory result) = _allocationCampaign.isEligibleAction.to.staticcall(callData);
            if (success == false) revert CallFailed(msg.sender, _campaignId, _account);
            return abi.decode(result, (bool));
        }
    }

    /// @inheritdoc IAllocatorStrategy
    function getClaimeableAmount(
        uint256 _campaignId,
        address _account,
        bytes calldata _auxData
    ) public view override returns (uint256 amount) {
        if (canClaim(_campaignId, _account, _auxData) == false) return 0;
        AllocationCampaign storage _allocationCampaign = allocationCampaigns[msg.sender][_campaignId];

        bytes memory callData = abi.encodeWithSelector(
            _allocationCampaign.getPayoutAmountAction.functionSelector,
            _account
        );
        (bool success, bytes memory result) = _allocationCampaign.getPayoutAmountAction.to.staticcall(callData);
        if (success == false) revert CallFailed(msg.sender, _campaignId, _account);
        return abi.decode(result, (uint256));
    }

    /// @notice Exposes the internal `_updateEpochDuration` function for testing.
    /// @dev This function is protected by DaoAuthorizable.
    function updateEpochDuration(uint256 _newEpochDuration) public {
        if (msg.sender != address(dao())) revert OnlyDAOAllowed(msg.sender);
        _updateEpochDuration(_newEpochDuration);
    }

    /// @notice Exposes the internal `_updateClaimPeriodStatus` function for testing.
    /// @dev This function is protected by DaoAuthorizable.
    function updateClaimPeriodStatus(bool _isOpen) public {
        if (msg.sender != address(dao())) revert OnlyDAOAllowed(msg.sender);
        _updateClaimPeriodStatus(_isOpen);
    }
}
