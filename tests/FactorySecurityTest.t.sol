// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { IDAO } from "@aragon/commons/dao/IDAO.sol";
import { Action } from "@aragon/commons/executors/IExecutor.sol";
import { AllocatorStrategyFactory } from "../src/factories/AllocatorStrategyFactory.sol";
import { ActionEncoderFactory } from "../src/factories/ActionEncoderFactory.sol";
import { ICapitalDistributorPlugin } from "../src/interfaces/ICapitalDistributorPlugin.sol";
import { IAllocatorStrategy } from "../src/interfaces/IAllocatorStrategy.sol";
import { IPayoutActionEncoder } from "../src/interfaces/IPayoutActionEncoder.sol";

/// @title FactorySecurityTest
/// @notice Tests that factory functions are protected by ERC165 interface checks
contract FactorySecurityTest is Test {
    AllocatorStrategyFactory allocatorFactory;
    ActionEncoderFactory actionEncoderFactory;

    MockDAO mockDAO;
    MockUnauthorizedCaller unauthorizedCaller;
    MockCapitalDistributorPlugin authorizedCaller;

    function setUp() public {
        allocatorFactory = new AllocatorStrategyFactory();
        actionEncoderFactory = new ActionEncoderFactory();
        mockDAO = new MockDAO();
        unauthorizedCaller = new MockUnauthorizedCaller();
        authorizedCaller = new MockCapitalDistributorPlugin();
    }

    /// @notice Test that unauthorized caller cannot deploy strategies
    function test_UnauthorizedCannotDeployStrategy() public {
        vm.startPrank(address(unauthorizedCaller));

        vm.expectRevert(
            abi.encodeWithSelector(AllocatorStrategyFactory.UnauthorizedCaller.selector, address(unauthorizedCaller))
        );
        allocatorFactory.deployStrategy(bytes32("test-strategy"), IDAO(address(mockDAO)), "");

        vm.stopPrank();
    }

    /// @notice Test that unauthorized caller cannot deploy action encoders
    function test_UnauthorizedCannotDeployActionEncoder() public {
        vm.startPrank(address(unauthorizedCaller));

        vm.expectRevert(
            abi.encodeWithSelector(ActionEncoderFactory.UnauthorizedCaller.selector, address(unauthorizedCaller))
        );
        actionEncoderFactory.deployActionEncoder(bytes32("test-encoder"), IDAO(address(mockDAO)), "");

        vm.stopPrank();
    }

    /// @notice Test that getOrDeployStrategy also rejects unauthorized callers
    function test_UnauthorizedCannotGetOrDeployStrategy() public {
        vm.startPrank(address(unauthorizedCaller));

        vm.expectRevert(
            abi.encodeWithSelector(AllocatorStrategyFactory.UnauthorizedCaller.selector, address(unauthorizedCaller))
        );
        allocatorFactory.getOrDeployStrategy(bytes32("test-strategy"), IDAO(address(mockDAO)), "");

        vm.stopPrank();
    }

    /// @notice Test that getOrDeployActionEncoder also rejects unauthorized callers
    function test_UnauthorizedCannotGetOrDeployActionEncoder() public {
        vm.startPrank(address(unauthorizedCaller));

        vm.expectRevert(
            abi.encodeWithSelector(ActionEncoderFactory.UnauthorizedCaller.selector, address(unauthorizedCaller))
        );
        actionEncoderFactory.getOrDeployActionEncoder(bytes32("test-encoder"), IDAO(address(mockDAO)), "");

        vm.stopPrank();
    }

    /// @notice Test that authorized CapitalDistributorPlugin can deploy strategies
    function test_AuthorizedCanDeployStrategy() public {
        // First register a proper mock strategy type
        bytes32 strategyId = bytes32("mock-strategy");
        address mockImpl = address(new MockStrategyProper());

        allocatorFactory.registerStrategyType(strategyId, mockImpl, "Mock Strategy", address(0), 0);

        vm.startPrank(address(authorizedCaller));

        // This should succeed because authorizedCaller implements ICapitalDistributorPlugin
        address deployedStrategy = allocatorFactory.deployStrategy(
            strategyId,
            IDAO(address(mockDAO)),
            abi.encode(uint256(1000)) // Provide proper initialization data
        );

        assertTrue(deployedStrategy != address(0), "Strategy should be deployed");

        vm.stopPrank();
    }

    /// @notice Test that authorized CapitalDistributorPlugin can use getOrDeployStrategy
    function test_AuthorizedCanGetOrDeployStrategy() public {
        // First register a proper mock strategy type
        bytes32 strategyId = bytes32("mock-strategy-2");
        address mockImpl = address(new MockStrategyProper());

        allocatorFactory.registerStrategyType(strategyId, mockImpl, "Mock Strategy 2", address(0), 0);

        vm.startPrank(address(authorizedCaller));

        // First call should deploy
        address deployedStrategy1 =
            allocatorFactory.getOrDeployStrategy(strategyId, IDAO(address(mockDAO)), abi.encode(uint256(2000)));

        assertTrue(deployedStrategy1 != address(0), "Strategy should be deployed");

        // Second call with same parameters should return existing
        address deployedStrategy2 =
            allocatorFactory.getOrDeployStrategy(strategyId, IDAO(address(mockDAO)), abi.encode(uint256(2000)));

        assertEq(deployedStrategy1, deployedStrategy2, "Should return same deployed strategy");

        vm.stopPrank();
    }

    /// @notice Test that authorized CapitalDistributorPlugin can deploy action encoders
    function test_AuthorizedCanDeployActionEncoder() public {
        // First register a proper mock action encoder type
        bytes32 encoderId = bytes32("mock-encoder");
        address mockImpl = address(new MockActionEncoderProper());

        actionEncoderFactory.registerActionEncoder(encoderId, mockImpl, "Mock Action Encoder");

        vm.startPrank(address(authorizedCaller));

        // This should succeed because authorizedCaller implements ICapitalDistributorPlugin
        address deployedEncoder = address(
            actionEncoderFactory.deployActionEncoder(
                encoderId,
                IDAO(address(mockDAO)),
                abi.encode(address(0x123)) // Provide proper initialization data
            )
        );

        assertTrue(deployedEncoder != address(0), "Action encoder should be deployed");

        vm.stopPrank();
    }

    /// @notice Test that authorized CapitalDistributorPlugin can use getOrDeployActionEncoder
    function test_AuthorizedCanGetOrDeployActionEncoder() public {
        // First register a proper mock action encoder type
        bytes32 encoderId = bytes32("mock-encoder-2");
        address mockImpl = address(new MockActionEncoderProper());

        actionEncoderFactory.registerActionEncoder(encoderId, mockImpl, "Mock Action Encoder 2");

        vm.startPrank(address(authorizedCaller));

        // First call should deploy
        address deployedEncoder1 = address(
            actionEncoderFactory.getOrDeployActionEncoder(encoderId, IDAO(address(mockDAO)), abi.encode(address(0x456)))
        );

        assertTrue(deployedEncoder1 != address(0), "Action encoder should be deployed");

        // Second call with same parameters should return existing
        address deployedEncoder2 = address(
            actionEncoderFactory.getOrDeployActionEncoder(encoderId, IDAO(address(mockDAO)), abi.encode(address(0x456)))
        );

        assertEq(deployedEncoder1, deployedEncoder2, "Should return same deployed encoder");

        vm.stopPrank();
    }
}

/// @notice Mock DAO for testing
contract MockDAO {
    function hasPermission(address, address, bytes32, bytes memory) external pure returns (bool) {
        return true;
    }
}

/// @notice Mock unauthorized caller that doesn't implement ICapitalDistributorPlugin
contract MockUnauthorizedCaller {
// This contract intentionally does NOT implement ICapitalDistributorPlugin
}

/// @notice Mock authorized caller that implements ICapitalDistributorPlugin
contract MockCapitalDistributorPlugin is ICapitalDistributorPlugin {
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
    ) external pure returns (uint256) {
        return 0;
    }

    function claimCampaignPayout(
        uint256,
        address,
        bytes calldata,
        bytes calldata
    ) external pure returns (uint256) {
        return 0;
    }

    function claimCampaignPayoutToAddress(
        uint256,
        address,
        bytes calldata,
        bytes calldata
    ) external pure returns (uint256) {
        return 0;
    }

    function batchClaimCampaignPayout(
        uint256[] calldata,
        address[] calldata,
        bytes[] calldata,
        bytes[] calldata
    ) external pure returns (uint256[] memory) {
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

/// @notice Mock strategy implementation for testing
contract MockStrategy {
    function strategyId() external pure returns (bytes32) {
        return bytes32("mock-strategy");
    }

    function initialize(address, uint256, bytes memory) external {
        // Mock initialization
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

/// @notice Mock action encoder implementation for testing
contract MockActionEncoder {
    function encoderId() external pure returns (bytes32) {
        return bytes32("mock-encoder");
    }

    function initialize(address, bytes memory) external {
        // Mock initialization
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

/// @notice Proper mock strategy implementation that works with factory deployment
contract MockStrategyProper is IAllocatorStrategy {
    bool public initialized;
    uint256 public testValue;

    function strategyId() external pure returns (bytes32) {
        return bytes32("mock-strategy");
    }

    function initialize(bytes32, address, address, bytes memory _data) external {
        require(!initialized, "Already initialized");
        initialized = true;
        if (_data.length > 0) {
            testValue = abi.decode(_data, (uint256));
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAllocatorStrategy).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // Mock functions required by IAllocatorStrategy
    function setAllocationCampaign(uint256, bytes calldata) external {
        // Mock implementation - do nothing
    }

    function getTotalClaimableAmount(uint256, address, bytes memory) external pure returns (uint256) {
        return 100e18;
    }

    function getFeeConfiguration() external pure returns (address, uint32) {
        return (address(0), 0);
    }

    function getInitializationEncodingTypes() external pure returns (string memory) {
        return "uint256";
    }

    function getCreationEncodingTypes() external pure returns (string memory) {
        return "";
    }

    function getClaimEncodingTypes() external pure returns (string memory) {
        return "";
    }
}

/// @notice Proper mock action encoder implementation that works with factory deployment
contract MockActionEncoderProper is IPayoutActionEncoder {
    bool public initialized;
    address public testAddress;

    function encoderId() external pure returns (bytes32) {
        return bytes32("mock-encoder");
    }

    function initialize(bytes32, address, address, bytes memory _data) external {
        require(!initialized, "Already initialized");
        initialized = true;
        if (_data.length > 0) {
            testAddress = abi.decode(_data, (address));
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IPayoutActionEncoder).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // Mock functions required by IPayoutActionEncoder
    function setupCampaign(uint256, bytes calldata) external {
        // Mock setup
    }

    function getCreationEncodingTypes() external pure returns (string memory) {
        return "address";
    }

    function getClaimEncodingTypes() external pure returns (string memory) {
        return "";
    }

    function buildActions(
        IERC20,
        address,
        uint256,
        address,
        uint256,
        bytes calldata
    )
        external
        pure
        returns (Action[] memory actions)
    {
        actions = new Action[](0);
        return actions;
    }
}
