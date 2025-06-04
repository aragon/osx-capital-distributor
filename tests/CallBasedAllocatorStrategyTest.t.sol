// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {IPayoutActionEncoder} from "../src/interfaces/IPayoutActionEncoder.sol";
import {CapitalDistributorPlugin} from "../src/CapitalDistributorPlugin.sol";
import {AragonTest} from "./helpers/AragonTest.sol";
import {IAllocatorStrategy} from "../src/interfaces/IAllocatorStrategy.sol";
import {AllocatorStrategyMock} from "./mocks/AllocatorStrategyMock.sol";
import {IAllocatorStrategyFactory} from "../src/interfaces/IAllocatorStrategyFactory.sol";
import {CallBasedAllocatorStrategy} from "../src/allocatorStrategies/CallBasedAllocatorStrategy.sol";

import {MintableERC20} from "./mocks/MintableERC20.sol";
import {MockVoter} from "./mocks/MockVoter.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract CallBasedAllocatorStrategyTest is AragonTest {
    CapitalDistributorPlugin capitalDistributorPlugin;
    CallBasedAllocatorStrategy strategy;
    MintableERC20 token;
    MockVoter voter;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        // Instantiate the contract-under-test.
        capitalDistributorPlugin = CapitalDistributorPlugin(pluginAddress[0]);
        token = new MintableERC20();
        strategy = new CallBasedAllocatorStrategy();
        voter = new MockVoter();
        vm.startPrank(address(createdDAO));
        allocatorStrategyFactory.registerStrategyType(toBytes32("call-based-strategy"), address(strategy), "");
    }

    function test_CreateCampaign() public {
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        IAllocatorStrategyFactory.DeploymentParams memory allocatorDeploymentParams = IAllocatorStrategyFactory
            .DeploymentParams({dao: createdDAO, epochDuration: 1 days, claimOpen: true, auxData: ""});

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            0,
            metadata,
            toBytes32("call-based-strategy"),
            allocatorDeploymentParams,
            getAllocationCampaignAuxData(voter),
            address(0),
            IERC20(token),
            bytes32(0),
            metadata
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        assertEq(campaign.metadataURI, metadata, "Metadata not equal");
        assertTrue(address(campaign.allocationStrategy) != address(0), "Allocation strategy not set");
        assertEq(address(campaign.vault), address(0), "Vault not equal");
    }

    function test_CannotCreateCampaignWithoutPermissions() public {
        vm.startPrank(address(alice));
        bytes memory metadata = "";
        IAllocatorStrategyFactory.DeploymentParams memory allocatorDeploymentParams = IAllocatorStrategyFactory
            .DeploymentParams({dao: createdDAO, epochDuration: 1 days, claimOpen: true, auxData: ""});

        vm.expectRevert();
        capitalDistributorPlugin.createCampaign(
            0,
            metadata,
            toBytes32("call-based-strategy"),
            allocatorDeploymentParams,
            getAllocationCampaignAuxData(voter),
            address(0),
            IERC20(token),
            bytes32(0),
            metadata
        );
    }

    function test_PayoutIsSent() public {
        token.mint(address(createdDAO), 1 ether);
        voter.mint(alice, 1 ether);
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        IAllocatorStrategyFactory.DeploymentParams memory allocatorDeploymentParams = IAllocatorStrategyFactory
            .DeploymentParams({dao: createdDAO, epochDuration: 1 days, claimOpen: true, auxData: ""});

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            0,
            metadata,
            toBytes32("call-based-strategy"),
            allocatorDeploymentParams,
            getAllocationCampaignAuxData(voter),
            address(0),
            IERC20(token),
            bytes32(0),
            metadata
        );
        // We create the campaign in the allocation strategy as well
        vm.stopPrank();
        vm.startPrank(address(capitalDistributorPlugin));

        assertEq(token.balanceOf(address(createdDAO)), 1 ether, "DAO doesn't have funds");
        assertEq(token.balanceOf(alice), 0 ether, "Alice has funds");
        assertEq(voter.balanceOf(alice), 1 ether, "Alice hasn't voter funds");

        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, metadata);

        assertEq(token.balanceOf(address(createdDAO)), 0 ether, "DAO has funds");
        assertEq(token.balanceOf(alice), 1 ether, "Alice has funds");
    }

    function getAllocationCampaignAuxData(MockVoter _voter) public pure returns (bytes memory auxData) {
        CallBasedAllocatorStrategy.ActionCall memory isEligibleCall = CallBasedAllocatorStrategy.ActionCall(
            address(_voter),
            _voter.isVoting.selector
        );

        CallBasedAllocatorStrategy.ActionCall memory getPayoutAmountCall = CallBasedAllocatorStrategy.ActionCall(
            address(_voter),
            _voter.balanceOf.selector
        );
        auxData = abi.encode(isEligibleCall, getPayoutAmountCall);
    }
}
