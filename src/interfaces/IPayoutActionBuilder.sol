// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {Action, IExecutor} from "@aragon/commons/executors/IExecutor.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @title IPayoutActionBuilder
/// @notice Interface for contracts that construct the DAO actions required to execute a payout.
interface IPayoutActionBuilder {
    /**
     * @notice Constructs the sequence of actions required to execute a payout.
     * @param _token The token being distributed.
     * @param _recipient The ultimate beneficiary of the payout.
     * @param _amount The amount of tokens to be paid out.
     * @param _caller The address of the CapitalDistributorPlugin calling this builder.
     * @param _campaignId The ID of the campaign for which this payout is being made.
     * @return actions An array of `Action` structs to be executed by the DAO.
     */
    function buildActions(
        IERC20 _token,
        address _recipient,
        uint256 _amount,
        address _caller, // Added for context, might be useful for builders
        uint256 _campaignId // Added for context
    ) external view returns (Action[] memory actions);
}
