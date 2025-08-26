// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.29 <0.9.0;


import {CapitalDistributorPlugin} from "../src/CapitalDistributorPlugin.sol";
import {AragonTest} from "./helpers/AragonTest.sol";
import {MintableERC20} from "./mocks/MintableERC20.sol";
import {AllocatorStrategyMock} from "./mocks/AllocatorStrategyMock.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @title CampaignStateManagementTest
/// @notice Tests for the new campaign state management (ACTIVE/PAUSED/ENDED)
contract CampaignStateManagementTest is AragonTest {
    CapitalDistributorPlugin capitalDistributorPlugin;
    MintableERC20 token;
    AllocatorStrategyMock strategy;
    
    function setUp() public virtual {
        capitalDistributorPlugin = CapitalDistributorPlugin(pluginAddress[0]);
        token = new MintableERC20();
        strategy = new AllocatorStrategyMock();
        allocatorStrategyFactory.registerStrategyType(toBytes32("mock-strategy"), address(strategy), "", address(0), 0);
    }
    
    function createBasicCampaign() internal returns (uint256 campaignId) {
        vm.startPrank(address(createdDAO));
        campaignId = capitalDistributorPlugin.createCampaign(
            "ipfs://test",
            toBytes32("mock-strategy"),
            "",
            "",
            IERC20(token),
            bytes32(0),
            "",
            false,
            0,
            0
        );
        vm.stopPrank();
    }

    /// @notice Test that campaigns are created in ACTIVE state
    function test_CampaignsStartActive() public {
        uint256 campaignId = createBasicCampaign();
        
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertTrue(campaign.state == CapitalDistributorPlugin.CampaignState.ACTIVE, "Campaign should start active");
        assertTrue(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be active via function");
    }

    /// @notice Test pausing an active campaign
    function test_PauseActiveCampaign() public {
        uint256 campaignId = createBasicCampaign();
        
        vm.startPrank(address(createdDAO));
        
        // Should emit CampaignPaused event
        vm.expectEmit(true, false, false, false);
        emit CapitalDistributorPlugin.CampaignPaused(campaignId);
        
        capitalDistributorPlugin.pauseCampaign(campaignId);
        
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertTrue(campaign.state == CapitalDistributorPlugin.CampaignState.PAUSED, "Campaign should be paused");
        assertFalse(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should not be active");
        
        vm.stopPrank();
    }

    /// @notice Test resuming a paused campaign
    function test_ResumePausedCampaign() public {
        uint256 campaignId = createBasicCampaign();
        
        vm.startPrank(address(createdDAO));
        
        // Pause first
        capitalDistributorPlugin.pauseCampaign(campaignId);
        
        // Should emit CampaignResumed event
        vm.expectEmit(true, false, false, false);
        emit CapitalDistributorPlugin.CampaignResumed(campaignId);
        
        // Resume
        capitalDistributorPlugin.resumeCampaign(campaignId);
        
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertTrue(campaign.state == CapitalDistributorPlugin.CampaignState.ACTIVE, "Campaign should be active again");
        assertTrue(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be active via function");
        
        vm.stopPrank();
    }

    /// @notice Test ending an active campaign
    function test_EndActiveCampaign() public {
        uint256 campaignId = createBasicCampaign();
        
        vm.startPrank(address(createdDAO));
        
        // Should emit CampaignEnded event
        vm.expectEmit(true, false, false, false);
        emit CapitalDistributorPlugin.CampaignEnded(campaignId);
        
        capitalDistributorPlugin.endCampaign(campaignId);
        
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertTrue(campaign.state == CapitalDistributorPlugin.CampaignState.ENDED, "Campaign should be ended");
        assertFalse(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should not be active");
        
        vm.stopPrank();
    }

    /// @notice Test ending a paused campaign
    function test_EndPausedCampaign() public {
        uint256 campaignId = createBasicCampaign();
        
        vm.startPrank(address(createdDAO));
        
        // Pause first
        capitalDistributorPlugin.pauseCampaign(campaignId);
        
        // Should emit CampaignEnded event
        vm.expectEmit(true, false, false, false);
        emit CapitalDistributorPlugin.CampaignEnded(campaignId);
        
        // End the paused campaign
        capitalDistributorPlugin.endCampaign(campaignId);
        
        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);
        assertTrue(campaign.state == CapitalDistributorPlugin.CampaignState.ENDED, "Campaign should be ended");
        assertFalse(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should not be active");
        
        vm.stopPrank();
    }

    /// @notice Test invalid state transitions
    function test_InvalidStateTransitions() public {
        uint256 campaignId = createBasicCampaign();
        
        vm.startPrank(address(createdDAO));
        
        // Cannot pause a non-active campaign 
        capitalDistributorPlugin.endCampaign(campaignId);
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.InvalidStateTransition.selector,
                campaignId,
                CapitalDistributorPlugin.CampaignState.ENDED,
                CapitalDistributorPlugin.CampaignState.PAUSED
            )
        );
        capitalDistributorPlugin.pauseCampaign(campaignId);
        
        vm.stopPrank();
    }
    
    /// @notice Test cannot resume non-paused campaign
    function test_CannotResumeNonPausedCampaign() public {
        uint256 campaignId = createBasicCampaign();
        
        vm.startPrank(address(createdDAO));
        
        // Try to resume active campaign
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.InvalidStateTransition.selector,
                campaignId,
                CapitalDistributorPlugin.CampaignState.ACTIVE,
                CapitalDistributorPlugin.CampaignState.ACTIVE
            )
        );
        capitalDistributorPlugin.resumeCampaign(campaignId);
        
        vm.stopPrank();
    }
    
    /// @notice Test cannot end already ended campaign
    function test_CannotEndAlreadyEndedCampaign() public {
        uint256 campaignId = createBasicCampaign();
        
        vm.startPrank(address(createdDAO));
        
        // End campaign
        capitalDistributorPlugin.endCampaign(campaignId);
        
        // Try to end again
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.InvalidStateTransition.selector,
                campaignId,
                CapitalDistributorPlugin.CampaignState.ENDED,
                CapitalDistributorPlugin.CampaignState.ENDED
            )
        );
        capitalDistributorPlugin.endCampaign(campaignId);
        
        vm.stopPrank();
    }

    /// @notice Test claiming works only on active campaigns
    function test_ClaimingOnlyWorksOnActiveCampaigns() public {
        token.mint(address(createdDAO), 10 ether);
        uint256 campaignId = createBasicCampaign();
        
        vm.startPrank(address(createdDAO));
        
        // Claiming should work on active campaign (would fail for other reasons but not state)
        // This test mainly verifies the state check is working
        
        // Pause campaign
        capitalDistributorPlugin.pauseCampaign(campaignId);
        
        // Claiming should fail on paused campaign
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.CampaignNotActive.selector,
                campaignId,
                CapitalDistributorPlugin.CampaignState.PAUSED
            )
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, address(this), "", "");
        
        // Resume campaign
        capitalDistributorPlugin.resumeCampaign(campaignId);
        
        // End campaign
        capitalDistributorPlugin.endCampaign(campaignId);
        
        // Claiming should fail on ended campaign
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.CampaignNotActive.selector,
                campaignId,
                CapitalDistributorPlugin.CampaignState.ENDED
            )
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, address(this), "", "");
        
        vm.stopPrank();
    }

    /// @notice Test safe merkle root update flow (pause -> update -> resume)
    function test_SafeMerkleRootUpdateFlow() public {
        uint256 campaignId = createBasicCampaign();
        
        vm.startPrank(address(createdDAO));
        
        // 1. Pause campaign to prevent front-running
        capitalDistributorPlugin.pauseCampaign(campaignId);
        
        // Verify no claims can be made during pause
        vm.expectRevert(
            abi.encodeWithSelector(
                CapitalDistributorPlugin.CampaignNotActive.selector,
                campaignId,
                CapitalDistributorPlugin.CampaignState.PAUSED
            )
        );
        capitalDistributorPlugin.claimCampaignPayout(campaignId, address(this), "", "");
        
        // 2. Update merkle root (would be done on MerkleDistributorStrategy)
        // Note: This is just demonstrating the flow - actual root updates are done on the strategy
        
        // 3. Resume campaign
        capitalDistributorPlugin.resumeCampaign(campaignId);
        
        // Verify campaign is active again
        assertTrue(capitalDistributorPlugin.isCampaignActive(campaignId), "Campaign should be active after resume");
        
        vm.stopPrank();
    }

    /// @notice Test authorization is required for state changes
    function test_OnlyAuthorizedCanChangeState() public {
        uint256 campaignId = createBasicCampaign();
        
        // Unauthorized user cannot pause
        vm.startPrank(address(0x1234));
        vm.expectRevert(); // Should revert due to auth
        capitalDistributorPlugin.pauseCampaign(campaignId);
        vm.stopPrank();
        
        // Authorized user can pause
        vm.startPrank(address(createdDAO));
        capitalDistributorPlugin.pauseCampaign(campaignId);
        vm.stopPrank();
        
        // Unauthorized user cannot resume
        vm.startPrank(address(0x1234));
        vm.expectRevert(); // Should revert due to auth
        capitalDistributorPlugin.resumeCampaign(campaignId);
        vm.stopPrank();
        
        // Authorized user can resume
        vm.startPrank(address(createdDAO));
        capitalDistributorPlugin.resumeCampaign(campaignId);
        vm.stopPrank();
    }
}