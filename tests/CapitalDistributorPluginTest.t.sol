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
import {VaultDepositPayoutActionEncoder} from "../src/payoutActionEncoders/VaultDepositPayoutActionEncoder.sol";
import {IAllocatorStrategyFactory} from "../src/interfaces/IAllocatorStrategyFactory.sol";

import {MintableERC20} from "./mocks/MintableERC20.sol";
import {ERC4626Mock} from "./mocks/ERC4626Mock.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract CapitalDistributorPluginTest is AragonTest {
    CapitalDistributorPlugin capitalDistributorPlugin;
    AllocatorStrategyMock strategy;
    MintableERC20 token;
    ERC4626Mock vaultToSendTokens;
    VaultDepositPayoutActionEncoder vaultDepositActionEncoder;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        // Instantiate the contract-under-test.
        capitalDistributorPlugin = CapitalDistributorPlugin(pluginAddress[0]);
        token = new MintableERC20();
        strategy = new AllocatorStrategyMock();
        // Add the strategy to the StrategyFactory
        allocatorStrategyFactory.registerStrategyType(toBytes32("mock-strategy"), address(strategy), "");

        vaultToSendTokens = new ERC4626Mock(address(token));
    }

    function test_CreateCampaign() public {
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";

        IAllocatorStrategyFactory.DeploymentParams memory allocatorDeploymentParams = IAllocatorStrategyFactory
            .DeploymentParams({auxData: ""});

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("mock-strategy"),
            allocatorDeploymentParams,
            metadata, // Doesn't have to be metadata, just empty bytes
            IERC20(token),
            bytes32(0),
            metadata, // Doesn't have to be metadata, just empty bytes
            false
        );

        CapitalDistributorPlugin.Campaign memory campaign = capitalDistributorPlugin.getCampaign(campaignId);

        assertEq(campaign.metadataURI, metadata, "Metadata not equal");
        assertTrue(address(campaign.allocationStrategy) != address(0), "Allocation strategy not set");
    }

    function test_CannotCreateCampaignWithoutPermissions() public {
        vm.startPrank(address(alice));
        bytes memory metadata = "";
        IAllocatorStrategyFactory.DeploymentParams memory allocatorDeploymentParams = IAllocatorStrategyFactory
            .DeploymentParams({auxData: ""});

        vm.expectRevert();
        capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("mock-strategy"),
            allocatorDeploymentParams,
            metadata, // Doesn't have to be metadata, just empty bytes
            IERC20(token),
            bytes32(0),
            metadata, // Doesn't have to be metadata, just empty bytes
            false
        );
    }

    function test_PayoutIsSent() public {
        token.mint(address(createdDAO), 1 ether);
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        IAllocatorStrategyFactory.DeploymentParams memory allocatorDeploymentParams = IAllocatorStrategyFactory
            .DeploymentParams({auxData: ""});

        uint256 campaignId = capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("mock-strategy"),
            allocatorDeploymentParams,
            metadata, // Doesn't have to be metadata, just empty bytes
            IERC20(token),
            bytes32(0),
            metadata, // Doesn't have to be metadata, just empty bytes
            false
        );

        assertEq(token.balanceOf(address(createdDAO)), 1 ether, "DAO doesn't have funds");
        assertEq(token.balanceOf(alice), 0 ether, "Alice has funds");
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, metadata);
        assertEq(token.balanceOf(address(createdDAO)), 0 ether, "DAO has funds");
        assertEq(token.balanceOf(alice), 1 ether, "Alice has funds");
    }

    function test_PayoutIsSentToVault() public {
        token.mint(address(createdDAO), 1 ether);
        vm.startPrank(address(createdDAO));
        bytes memory metadata = "";
        IAllocatorStrategyFactory.DeploymentParams memory allocatorDeploymentParams = IAllocatorStrategyFactory
            .DeploymentParams({auxData: ""});

        uint256 campaignId = 0;

        capitalDistributorPlugin.createCampaign(
            metadata,
            toBytes32("mock-strategy"),
            allocatorDeploymentParams,
            metadata, // Doesn't have to be metadata, just empty bytes
            IERC20(token),
            toBytes32("vault-deposit-encoder"),
            abi.encode(address(vaultToSendTokens)),
            false
        );

        assertEq(token.balanceOf(address(createdDAO)), 1 ether, "DAO doesn't have funds");
        assertEq(token.balanceOf(alice), 0 ether, "Alice has funds");
        capitalDistributorPlugin.claimCampaignPayout(campaignId, alice, metadata);
        assertEq(token.balanceOf(address(createdDAO)), 0 ether, "DAO has funds");
        assertEq(token.balanceOf(address(vaultToSendTokens)), 1 ether, "Vault has funds");
    }
}
