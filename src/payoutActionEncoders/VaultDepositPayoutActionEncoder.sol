// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {IPayoutActionEncoder} from "../interfaces/IPayoutActionEncoder.sol";
import {Action} from "@aragon/commons/executors/IExecutor.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {DaoAuthorizable} from "@aragon/commons/permission/auth/DaoAuthorizable.sol";

/// @title IVault
/// @notice A generic interface for a vault that this encoder can interact with.
/// Assumes a deposit function that takes a recipient and an amount.
interface IVault {
    function deposit(uint256 _amount, address _recipient) external;
}

/// @title VaultDepositPayoutActionEncoder
/// @notice An IPayoutActionEncoder that approves tokens for a campaign-specific vault and then calls its deposit function.
/// @dev This contract is DaoAuthorizable. The DAO controlling this encoder instance
///      must grant permission for `setCampaignVault`.
contract VaultDepositPayoutActionEncoder is IPayoutActionEncoder, DaoAuthorizable {
    /// @notice Permission ID required to call `setCampaignVault`.
    bytes32 public constant SET_VAULT_PERMISSION_ID = keccak256("SET_VAULT_PERMISSION");

    /// @notice Mapping from campaignId to the vault address for that campaign.
    mapping(uint256 => address) public campaignVaults;

    /// @notice Emitted when a vault address is set for a campaign.
    event CampaignVaultSet(uint256 indexed campaignId, address indexed vaultAddress, address indexed setter);

    /// @notice Thrown if the amount to payout is zero.
    error AmountCannotBeZero();
    /// @notice Thrown if no vault address is configured for the given campaignId.
    error VaultNotSetForCampaign(uint256 campaignId);
    /// @notice Thrown if the vault address to be set is the zero address.
    error ZeroAddressNotAllowed();
    /// @notice Thrown if the call is done by any address but the DAO
    error OnlyDAO();

    /**
     * @notice Constructor to initialize DaoAuthorizable with the DAO.
     * @param _dao The IDAO interface of the DAO that will manage permissions for this encoder.
     */
    constructor(IDAO _dao) DaoAuthorizable(_dao) {}

    /**
     * @notice Sets or updates the vault address for a specific campaign.
     * @dev Requires `SET_VAULT_PERMISSION_ID` granted to the caller by the DAO.
     * @param _campaignId The ID of the campaign.
     * @param _vaultAddress The address of the vault contract for this campaign.
     */
    function setCampaignVault(uint256 _campaignId, address _vaultAddress) external {
        if (msg.sender != address(dao())) revert OnlyDAO();
        if (_vaultAddress == address(0)) {
            revert ZeroAddressNotAllowed();
        }
        campaignVaults[_campaignId] = _vaultAddress;
        emit CampaignVaultSet(_campaignId, _vaultAddress, msg.sender);
    }

    /**
     * @inheritdoc IPayoutActionEncoder
     * @dev This implementation creates two actions:
     *      1. Approve the campaign-specific `vaultAddress` to spend `_amount` of `_token`.
     *      2. Call `deposit(_recipient, _amount)` on that `vaultAddress`.
     *      The `_campaignId` is used to look up the correct vault address.
     *      The `_caller` (CapitalDistributorPlugin) is not directly used but is available.
     */
    function buildActions(
        IERC20 _token,
        address _recipient,
        uint256 _amount,
        address, // _caller - not used in this specific encoder logic
        uint256 _campaignId
    ) external view override returns (Action[] memory actions) {
        if (_amount == 0) {
            revert AmountCannotBeZero();
        }

        address vaultAddress = campaignVaults[_campaignId];
        if (vaultAddress == address(0)) {
            revert VaultNotSetForCampaign(_campaignId);
        }

        actions = new Action[](2);

        // Action 1: Approve the vault to spend the token
        actions[0] = Action({
            to: address(_token),
            value: 0,
            data: abi.encodeCall(IERC20.approve, (vaultAddress, _amount))
        });

        // Action 2: Call deposit on the vault
        actions[1] = Action({to: vaultAddress, value: 0, data: abi.encodeCall(IVault.deposit, (_amount, _recipient))});

        return actions;
    }
}
