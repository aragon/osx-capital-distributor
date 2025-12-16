// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import {
    VotingEscrowLockPayoutActionEncoder
} from "../../src/payoutActionEncoders/VotingEscrowLockPayoutActionEncoder.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { Action } from "@aragon/commons/executors/IExecutor.sol";
import { IVotingEscrowIncreasing } from "../../src/interfaces/IVotingEscrowIncreasing.sol";

contract VotingEscrowLockPayoutActionEncoderTest is Test {
    VotingEscrowLockPayoutActionEncoder encoder;
    address mockVotingEscrow = 0x33fb4429d67b2d022B9d40751d44A9DA9A84d02b;
    IVotingEscrowIncreasing increasingVotingEscrow = IVotingEscrowIncreasing(mockVotingEscrow);
    address mockToken;
    address recipient = address(0x123);
    uint256 campaignId = 1;
    uint256 amount = 100e18;

    function setUp() public {
        encoder = new VotingEscrowLockPayoutActionEncoder();
        mockToken = address(0x789);

        // Setup campaign
        bytes memory auxData = encoder.encodeSetupCampaignParams(mockVotingEscrow);
        vm.prank(encoder.owner());
        encoder.setupCampaign(campaignId, auxData);
    }

    function test_BuildActions_ApprovesTokens() public {
        Action[] memory actions = encoder.buildActions(IERC20(mockToken), recipient, amount, address(0), campaignId, "");

        assertEq(actions.length, 2);

        // Check approve action
        assertEq(actions[0].to, mockToken);
        (address spender, uint256 approvedAmount) =
            abi.decode(slice(actions[0].data, 4, actions[0].data.length - 4), (address, uint256));
        assertEq(spender, mockVotingEscrow);
        assertEq(approvedAmount, amount);
    }

    function test_BuildActions_CallsCreateLockFor() public {
        Action[] memory actions = encoder.buildActions(IERC20(mockToken), recipient, amount, address(0), campaignId, "");

        // Check createLockFor action
        assertEq(actions[1].to, mockVotingEscrow);
        // Verify function selector is createLockFor(uint256,address)
        bytes4 selector = bytes4(actions[1].data);
        assertEq(selector, increasingVotingEscrow.createLockFor.selector);

        (uint256 lockAmount, address lockRecipient) =
            abi.decode(slice(actions[1].data, 4, actions[1].data.length - 4), (uint256, address));
        assertEq(lockAmount, amount);
        assertEq(lockRecipient, recipient);
    }

    function test_BuildActions_RevertsIfZeroAmount() public {
        vm.expectRevert(VotingEscrowLockPayoutActionEncoder.AmountCannotBeZero.selector);
        encoder.buildActions(IERC20(mockToken), recipient, 0, address(0), campaignId, "");
    }

    function test_BuildActions_RevertsIfVotingEscrowNotSet() public {
        vm.expectRevert(
            abi.encodeWithSelector(VotingEscrowLockPayoutActionEncoder.VotingEscrowNotSetForCampaign.selector, 999)
        );
        encoder.buildActions(
            IERC20(mockToken),
            recipient,
            amount,
            address(0),
            999, // Campaign not set
            ""
        );
    }

    function test_SetupCampaign_SetsVotingEscrowAddress() public {
        address newVotingEscrow = address(0xABC);
        bytes memory auxData = encoder.encodeSetupCampaignParams(newVotingEscrow);

        vm.expectEmit(true, true, true, true);
        emit VotingEscrowLockPayoutActionEncoder.CampaignVotingEscrowSet(
            campaignId + 1, newVotingEscrow, encoder.owner()
        );

        vm.prank(encoder.owner());
        encoder.setupCampaign(campaignId + 1, auxData);
        assertEq(encoder.campaignVotingEscrow(campaignId + 1), newVotingEscrow);
    }

    function test_SetupCampaign_RevertsIfZeroAddress() public {
        bytes memory auxData = encoder.encodeSetupCampaignParams(address(0));

        vm.prank(encoder.owner());
        vm.expectRevert(VotingEscrowLockPayoutActionEncoder.ZeroAddressNotAllowed.selector);
        encoder.setupCampaign(campaignId + 1, auxData);
    }

    function slice(bytes memory data, uint256 start, uint256 length) internal pure returns (bytes memory) {
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[i + start];
        }
        return result;
    }
}

