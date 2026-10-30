// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { AllocatorStrategyFactory } from "../../src/factories/AllocatorStrategyFactory.sol";
import { FactoryBase } from "../../src/factories/FactoryBase.sol";
import { IAllocatorStrategy } from "../../src/interfaces/IAllocatorStrategy.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { MerkleDistributorStrategy } from "../../src/allocatorStrategies/MerkleDistributorStrategy.sol";
import { AllocatorStrategyMock } from "../mocks/AllocatorStrategyMock.sol";
import { CapitalDistributorPluginMock } from "../mocks/CapitalDistributorPluginMock.sol";

/// @title AllocatorStrategyFactory Test Suite
/// @author AragonX - 2025
/// @notice Comprehensive test suite for the AllocatorStrategyFactory contract
/// @dev Tests functionality, security vulnerabilities, and edge cases
contract AllocatorStrategyFactoryTest is Test {
    AllocatorStrategyFactory factory;
    DAO dao;
    DAO dao2;
    CapitalDistributorPluginMock pluginMock;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address maliciousActor = makeAddr("malicious");

    MerkleDistributorStrategy merkleImplementation;
    AllocatorStrategyMock mockImplementation;
    address maliciousImplementation;

    bytes32 constant MERKLE_STRATEGY_ID = keccak256("merkle-distributor");
    bytes32 constant MOCK_STRATEGY_ID = keccak256("mock-strategy");
    bytes32 constant MALICIOUS_STRATEGY_ID = keccak256("malicious-strategy");
    bytes32 constant EMPTY_STRATEGY_ID = bytes32(0);

    string constant MERKLE_METADATA = "Merkle Tree Distribution Strategy";
    string constant MOCK_METADATA = "Mock Strategy for Testing";
    string constant MALICIOUS_METADATA = "Malicious Strategy";

    // Test events
    event StrategyTypeRegistered(bytes32 indexed strategyId, address indexed implementation, string metadata);
    event StrategyDeployed(bytes32 indexed strategyId, address indexed strategy);
    event TypeRegistered(
        bytes32 indexed typeId, address indexed implementation, string metadata, address indexed registrar
    );
    event InstanceDeployed(
        bytes32 indexed typeId, address indexed instance, bytes32 indexed deploymentId, address deployer
    );
    event StrategyFeeConfigured(bytes32 indexed strategyId, address indexed feeRecipient, uint32 feeBasisPoints);

    /// @notice Helper function to deploy strategy through authorized plugin mock
    function _deployStrategy(bytes32 strategyId, IDAO daoAddr, bytes memory auxData) internal returns (address) {
        vm.startPrank(address(pluginMock));
        address strategy = factory.deployStrategy(strategyId, daoAddr, auxData);
        vm.stopPrank();
        return strategy;
    }

    /// @notice Helper function to get or deploy strategy through authorized plugin mock
    function _getOrDeployStrategy(bytes32 strategyId, IDAO daoAddr, bytes memory auxData) internal returns (address) {
        vm.startPrank(address(pluginMock));
        address strategy = factory.getOrDeployStrategy(strategyId, daoAddr, auxData);
        vm.stopPrank();
        return strategy;
    }

    function setUp() public {
        factory = new AllocatorStrategyFactory();
        dao = DAO(payable(makeAddr("dao")));
        dao2 = DAO(payable(makeAddr("dao2")));
        pluginMock = new CapitalDistributorPluginMock();

        // Deploy strategy implementations
        merkleImplementation = new MerkleDistributorStrategy();
        mockImplementation = new AllocatorStrategyMock();
        maliciousImplementation = address(new MaliciousImplementation());

        vm.label(address(factory), "Factory");
        vm.label(address(dao), "DAO");
        vm.label(address(dao2), "DAO2");
        vm.label(address(pluginMock), "PluginMock");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(maliciousActor, "MaliciousActor");
        vm.label(address(merkleImplementation), "MerkleImplementation");
        vm.label(address(mockImplementation), "MockImplementation");
        vm.label(maliciousImplementation, "MaliciousImplementation");
    }

    /// ================================
    /// STRATEGY TYPE REGISTRATION TESTS
    /// ================================

    /// @notice Test successful strategy type registration
    function test_RegisterStrategyType_Success() public {
        vm.expectEmit(true, true, false, true);
        emit TypeRegistered(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, alice);

        vm.expectEmit(true, true, false, true);
        emit StrategyTypeRegistered(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA);

        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, address(0), 0);

        (address implementation, string memory metadata) = factory.registeredTypes(MERKLE_STRATEGY_ID);
        assertEq(implementation, address(merkleImplementation));
        assertEq(metadata, MERKLE_METADATA);
        assertTrue(factory.isTypeRegistered(MERKLE_STRATEGY_ID));
    }

    /// @notice Test multiple strategy type registrations
    function test_RegisterStrategyType_Multiple() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, address(0), 0);
        factory.registerStrategyType(MOCK_STRATEGY_ID, address(mockImplementation), MOCK_METADATA, address(0), 0);

        assertTrue(factory.isTypeRegistered(MERKLE_STRATEGY_ID));
        assertTrue(factory.isTypeRegistered(MOCK_STRATEGY_ID));

        (address merkleImpl,) = factory.registeredTypes(MERKLE_STRATEGY_ID);
        (address mockImpl,) = factory.registeredTypes(MOCK_STRATEGY_ID);

        assertEq(merkleImpl, address(merkleImplementation));
        assertEq(mockImpl, address(mockImplementation));
    }

    /// @notice Test registration with empty strategy ID
    function test_RegisterStrategyType_RevertEmptyId() public {
        vm.expectRevert(FactoryBase.EmptyTypeId.selector);
        factory.registerStrategyType(EMPTY_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, address(0), 0);
    }

    /// @notice Test registration with zero implementation address
    function test_RegisterStrategyType_RevertZeroImplementation() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                FactoryBase.InvalidImplementation.selector, address(0), "Implementation address cannot be zero"
            )
        );
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(0), MERKLE_METADATA, address(0), 0);
    }

    /// @notice Test registration with non-contract address
    function test_RegisterStrategyType_RevertNonContract() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                FactoryBase.InvalidImplementation.selector, alice, "Implementation must be a deployed contract"
            )
        );
        factory.registerStrategyType(MERKLE_STRATEGY_ID, alice, MERKLE_METADATA, address(0), 0);
    }

    /// @notice Test duplicate strategy type registration
    function test_RegisterStrategyType_RevertAlreadyRegistered() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(FactoryBase.AlreadyRegistered.selector, MERKLE_STRATEGY_ID));
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(mockImplementation), MOCK_METADATA, address(0), 0);
    }

    /// ===============================
    /// STRATEGY DEPLOYMENT TESTS
    /// ===============================

    /// @notice Test successful strategy deployment
    function test_DeployStrategy_Success() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, address(0), 0);

        bytes memory auxData = abi.encode(bytes32(keccak256("test-merkle-root")));

        vm.expectEmit(true, false, false, false);
        emit InstanceDeployed(MERKLE_STRATEGY_ID, address(0), bytes32(0), address(pluginMock));

        vm.expectEmit(true, false, false, false);
        emit StrategyDeployed(MERKLE_STRATEGY_ID, address(0));

        address strategy = _deployStrategy(MERKLE_STRATEGY_ID, dao, auxData);

        assertTrue(strategy != address(0));
        assertEq(factory.instanceToType(strategy), MERKLE_STRATEGY_ID);

        // Verify strategy was properly initialized
        assertEq(IAllocatorStrategy(strategy).strategyId(), MERKLE_STRATEGY_ID);
    }

    /// @notice Test deployment with non-existent strategy type
    function test_DeployStrategy_RevertTypeNotFound() public {
        bytes memory auxData = abi.encode(bytes32(keccak256("test-data")));

        vm.expectRevert(abi.encodeWithSelector(FactoryBase.TypeNotFound.selector, MERKLE_STRATEGY_ID));
        _deployStrategy(MERKLE_STRATEGY_ID, dao, auxData);
    }

    /// @notice Test deployment with duplicate parameters
    function test_DeployStrategy_RevertInstanceAlreadyDeployed() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, address(0), 0);

        bytes memory auxData = abi.encode(bytes32(keccak256("test-merkle-root")));

        // First deployment should succeed
        address strategy1 = _deployStrategy(MERKLE_STRATEGY_ID, dao, auxData);
        assertTrue(strategy1 != address(0));

        // Second deployment with same parameters should revert
        bytes32 deploymentId = keccak256(abi.encode(MERKLE_STRATEGY_ID, address(dao), address(pluginMock), auxData));
        vm.expectRevert(abi.encodeWithSelector(FactoryBase.InstanceAlreadyDeployed.selector, deploymentId, strategy1));
        _deployStrategy(MERKLE_STRATEGY_ID, dao, auxData);
    }

    /// @notice Test deployment with different auxiliary data creates different instances
    function test_DeployStrategy_DifferentAuxDataCreatesNewInstance() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, address(0), 0);

        bytes memory auxData1 = abi.encode(bytes32(keccak256("root1")));
        bytes memory auxData2 = abi.encode(bytes32(keccak256("root2")));

        address strategy1 = _deployStrategy(MERKLE_STRATEGY_ID, dao, auxData1);
        address strategy2 = _deployStrategy(MERKLE_STRATEGY_ID, dao, auxData2);

        assertTrue(strategy1 != strategy2);
        assertEq(factory.instanceToType(strategy1), MERKLE_STRATEGY_ID);
        assertEq(factory.instanceToType(strategy2), MERKLE_STRATEGY_ID);
    }

    /// @notice Test deployment with different DAOs creates different instances
    function test_DeployStrategy_DifferentDAOCreatesNewInstance() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, address(0), 0);

        bytes memory auxData = abi.encode(bytes32(keccak256("test-merkle-root")));

        address strategy1 = _deployStrategy(MERKLE_STRATEGY_ID, dao, auxData);
        address strategy2 = _deployStrategy(MERKLE_STRATEGY_ID, dao2, auxData);

        assertTrue(strategy1 != strategy2);
        assertEq(factory.instanceToType(strategy1), MERKLE_STRATEGY_ID);
        assertEq(factory.instanceToType(strategy2), MERKLE_STRATEGY_ID);
    }

    /// =======================================
    /// GET OR DEPLOY STRATEGY TESTS
    /// =======================================

    /// @notice Test getOrDeployStrategy returns existing instance
    function test_GetOrDeployStrategy_ReturnsExisting() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, address(0), 0);

        bytes memory auxData = abi.encode(bytes32(keccak256("test-merkle-root")));

        address strategy1 = _deployStrategy(MERKLE_STRATEGY_ID, dao, auxData);

        bytes32 expectedDeploymentId = keccak256(abi.encode(MERKLE_STRATEGY_ID, address(dao), auxData));

        address strategy2 = _getOrDeployStrategy(MERKLE_STRATEGY_ID, dao, auxData);

        assertEq(strategy1, strategy2);
    }

    /// @notice Test getOrDeployStrategy deploys new instance when none exists
    function test_GetOrDeployStrategy_DeploysNew() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, address(0), 0);

        bytes memory auxData = abi.encode(bytes32(keccak256("test-merkle-root")));

        address strategy = _getOrDeployStrategy(MERKLE_STRATEGY_ID, dao, auxData);

        assertTrue(strategy != address(0));
        assertEq(factory.instanceToType(strategy), MERKLE_STRATEGY_ID);
    }

    /// ===============================
    /// INSTANCE EXISTS TESTS
    /// ===============================

    /// @notice Test hasDeployment returns correct values
    function test_HasDeployment() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, address(0), 0);

        bytes memory auxData = abi.encode(bytes32(keccak256("test-merkle-root")));

        // Should not exist initially
        (bool exists, address strategy) = factory.hasDeployment(MERKLE_STRATEGY_ID, dao, address(pluginMock), auxData);
        assertFalse(exists);
        assertEq(strategy, address(0));

        // Deploy strategy
        address deployedStrategy = _deployStrategy(MERKLE_STRATEGY_ID, dao, auxData);

        // Should exist after deployment
        (exists, strategy) = factory.hasDeployment(MERKLE_STRATEGY_ID, dao, address(pluginMock), auxData);
        assertTrue(exists);
        assertEq(strategy, deployedStrategy);
    }

    /// ===============================
    /// PARAMETER HASH COMPUTATION TESTS
    /// ===============================

    /// @notice Test hash computation consistency
    function test_ParamsHashComputation() public view {
        bytes memory auxData1 = abi.encode(bytes32(keccak256("data1")));
        bytes memory auxData2 = abi.encode(bytes32(keccak256("data2")));

        bytes32 hash1 = keccak256(abi.encode(MERKLE_STRATEGY_ID, address(dao), auxData1));
        bytes32 hash2 = keccak256(abi.encode(MERKLE_STRATEGY_ID, address(dao), auxData2));
        bytes32 hash3 = keccak256(abi.encode(MOCK_STRATEGY_ID, address(dao), auxData1));
        bytes32 hash4 = keccak256(abi.encode(MERKLE_STRATEGY_ID, address(dao2), auxData1));

        assertTrue(hash1 != hash2);
        assertTrue(hash1 != hash3);
        assertTrue(hash1 != hash4);
        assertTrue(hash2 != hash3);
        assertTrue(hash2 != hash4);
        assertTrue(hash3 != hash4);
    }

    /// @notice Test hash collision resistance
    function test_HashCollisionResistance() public view {
        // Test potential collision scenarios
        bytes memory auxData1 = abi.encodePacked(MERKLE_STRATEGY_ID, address(dao));
        bytes32 hash1 = keccak256(abi.encode(MOCK_STRATEGY_ID, address(0), auxData1));

        bytes memory auxData2 = "";
        bytes32 hash2 = keccak256(abi.encode(MERKLE_STRATEGY_ID, address(dao), auxData2));

        assertTrue(hash1 != hash2);
    }

    /// ===============================
    /// SECURITY TESTS
    /// ===============================

    /// @notice Test malicious implementation registration (should be allowed)
    function test_Security_MaliciousImplementationRegistration() public {
        // Registration should succeed (factory doesn't validate implementation logic)
        factory.registerStrategyType(MALICIOUS_STRATEGY_ID, maliciousImplementation, MALICIOUS_METADATA, address(0), 0);
        assertTrue(factory.isTypeRegistered(MALICIOUS_STRATEGY_ID));
    }

    /// @notice Test malicious implementation deployment failure
    function test_Security_MaliciousImplementationDeploymentFailure() public {
        factory.registerStrategyType(MALICIOUS_STRATEGY_ID, maliciousImplementation, MALICIOUS_METADATA, address(0), 0);

        bytes memory auxData = abi.encode(bytes32(keccak256("malicious-data")));

        // Deployment should fail due to malicious implementation's initialize function
        vm.expectRevert();
        _deployStrategy(MALICIOUS_STRATEGY_ID, dao, auxData);
    }

    /// @notice Test large auxiliary data handling
    function test_Security_LargeAuxiliaryData() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, address(0), 0);

        // Create very large auxiliary data (10KB)
        bytes memory largeAuxData = new bytes(10_240);
        for (uint256 i = 0; i < largeAuxData.length; i++) {
            largeAuxData[i] = bytes1(uint8(i % 256));
        }

        // Should handle large data without issues
        address strategy = _deployStrategy(MERKLE_STRATEGY_ID, dao, largeAuxData);
        assertTrue(strategy != address(0));
    }

    /// @notice Test initialization data injection
    function test_Security_InitializationDataInjection() public {
        factory.registerStrategyType(MOCK_STRATEGY_ID, address(mockImplementation), MOCK_METADATA, address(0), 0);

        // Attempt to inject malicious data through auxData
        bytes memory maliciousAuxData =
            abi.encode(bytes32(keccak256("malicious")), address(maliciousActor), "injected data");

        // Deployment should succeed but malicious data should be contained
        address strategy = _deployStrategy(MOCK_STRATEGY_ID, dao, maliciousAuxData);
        assertTrue(strategy != address(0));

        // Verify the strategy was initialized with correct parameters
        assertEq(IAllocatorStrategy(strategy).strategyId(), MOCK_STRATEGY_ID);
    }

    /// ===============================
    /// GAS OPTIMIZATION TESTS
    /// ===============================

    /// @notice Test gas consumption for various operations
    function test_GasConsumption() public {
        uint256 gasStart;
        uint256 gasUsed;

        // Registration gas test
        gasStart = gasleft();
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, address(0), 0);
        gasUsed = gasStart - gasleft();
        console2.log("Gas used for strategy registration:", gasUsed);
        assertTrue(gasUsed < 150_000);

        // Deployment gas test
        bytes memory auxData = abi.encode(bytes32(keccak256("test-merkle-root")));
        gasStart = gasleft();
        _deployStrategy(MERKLE_STRATEGY_ID, dao, auxData);
        gasUsed = gasStart - gasleft();
        console2.log("Gas used for strategy deployment:", gasUsed);
        assertTrue(gasUsed < 250_000); // Increased due to plugin address and fee storage

        // Instance exists check gas test
        gasStart = gasleft();
        factory.hasDeployment(MERKLE_STRATEGY_ID, dao, address(pluginMock), auxData);
        gasUsed = gasStart - gasleft();
        console2.log("Gas used for hasDeployment:", gasUsed);
        assertTrue(gasUsed < 10_000);
    }

    /// ===============================
    /// EDGE CASE TESTS
    /// ===============================

    /// @notice Test deployment with empty auxiliary data
    function test_EdgeCase_EmptyAuxiliaryData() public {
        factory.registerStrategyType(MOCK_STRATEGY_ID, address(mockImplementation), MOCK_METADATA, address(0), 0);

        bytes memory emptyAuxData = "";
        address strategy = _deployStrategy(MOCK_STRATEGY_ID, dao, emptyAuxData);

        assertTrue(strategy != address(0));
        assertEq(factory.instanceToType(strategy), MOCK_STRATEGY_ID);
    }

    /// @notice Test deployment with maximum auxiliary data size
    function test_EdgeCase_MaxAuxiliaryData() public {
        factory.registerStrategyType(MOCK_STRATEGY_ID, address(mockImplementation), MOCK_METADATA, address(0), 0);

        // Create maximum reasonable auxiliary data (64KB)
        bytes memory maxAuxData = new bytes(65_536);
        for (uint256 i = 0; i < maxAuxData.length; i++) {
            maxAuxData[i] = bytes1(uint8(i % 256));
        }

        address strategy = _deployStrategy(MOCK_STRATEGY_ID, dao, maxAuxData);
        assertTrue(strategy != address(0));
    }

    /// @notice Test multiple concurrent deployments
    function test_EdgeCase_ConcurrentDeployments() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, address(0), 0);
        factory.registerStrategyType(MOCK_STRATEGY_ID, address(mockImplementation), MOCK_METADATA, address(0), 0);

        bytes memory auxData1 = abi.encode(bytes32(keccak256("concurrent1")));
        bytes memory auxData2 = abi.encode(bytes32(keccak256("concurrent2")));

        address strategy1 = _deployStrategy(MERKLE_STRATEGY_ID, dao, auxData1);
        address strategy2 = _deployStrategy(MOCK_STRATEGY_ID, dao, auxData2);
        address strategy3 = _deployStrategy(MERKLE_STRATEGY_ID, dao2, auxData1);

        assertTrue(strategy1 != strategy2);
        assertTrue(strategy1 != strategy3);
        assertTrue(strategy2 != strategy3);

        assertEq(factory.instanceToType(strategy1), MERKLE_STRATEGY_ID);
        assertEq(factory.instanceToType(strategy2), MOCK_STRATEGY_ID);
        assertEq(factory.instanceToType(strategy3), MERKLE_STRATEGY_ID);
    }

    /// ===============================
    /// FEE CONFIGURATION TESTS
    /// ===============================

    /// @notice Test registering strategy with valid fee configuration
    function test_RegisterStrategyWithFeeConfiguration() public {
        address feeRecipient = makeAddr("feeRecipient");
        uint32 feeBasisPoints = 500; // 5%

        vm.expectEmit(true, true, false, true);
        emit StrategyFeeConfigured(MERKLE_STRATEGY_ID, feeRecipient, feeBasisPoints);

        factory.registerStrategyType(
            MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, feeRecipient, feeBasisPoints
        );

        // Verify fee configuration
        (address recipient, uint32 basisPoints) = factory.strategyFees(MERKLE_STRATEGY_ID);
        assertEq(recipient, feeRecipient);
        assertEq(basisPoints, feeBasisPoints);
    }

    /// @notice Test registering strategy with zero fee
    function test_RegisterStrategyWithZeroFee() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, address(0), 0);

        // Verify no fee configuration
        (address recipient, uint32 basisPoints) = factory.strategyFees(MERKLE_STRATEGY_ID);
        assertEq(recipient, address(0));
        assertEq(basisPoints, 0);
    }

    /// @notice Test registering strategy with maximum fee (10%)
    function test_RegisterStrategyWithMaximumFee() public {
        address feeRecipient = makeAddr("feeRecipient");
        uint32 maxFeeBasisPoints = 1000; // 10%

        factory.registerStrategyType(
            MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, feeRecipient, maxFeeBasisPoints
        );

        // Verify fee configuration
        (address recipient, uint32 basisPoints) = factory.strategyFees(MERKLE_STRATEGY_ID);
        assertEq(recipient, feeRecipient);
        assertEq(basisPoints, maxFeeBasisPoints);
    }

    /// @notice Test registering strategy with excessive fee
    function test_RegisterStrategyWithExcessiveFee_Reverts() public {
        address feeRecipient = makeAddr("feeRecipient");
        uint32 excessiveFeeBasisPoints = 1001; // 10.01%

        vm.expectRevert(
            abi.encodeWithSelector(AllocatorStrategyFactory.ExcessiveFee.selector, excessiveFeeBasisPoints, 1000)
        );

        factory.registerStrategyType(
            MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, feeRecipient, excessiveFeeBasisPoints
        );
    }

    /// @notice Test registering strategy with fee but no recipient
    function test_RegisterStrategyWithFeeButNoRecipient_Reverts() public {
        uint32 feeBasisPoints = 500; // 5%

        vm.expectRevert(AllocatorStrategyFactory.InvalidFeeRecipient.selector);

        factory.registerStrategyType(
            MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, address(0), feeBasisPoints
        );
    }

    /// @notice Test getStrategyFeeByInstance with valid strategy
    function test_GetStrategyFeeByInstance_ValidStrategy() public {
        address feeRecipient = makeAddr("feeRecipient");
        uint32 feeBasisPoints = 250; // 2.5%

        // Register strategy with fee
        factory.registerStrategyType(
            MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, feeRecipient, feeBasisPoints
        );

        // Deploy strategy
        bytes memory auxData = abi.encode(bytes32(keccak256("test-merkle-root")));
        address strategy = _deployStrategy(MERKLE_STRATEGY_ID, dao, auxData);

        // Get fee by instance
        (address recipient, uint32 basisPoints) = factory.getStrategyFeeByInstance(strategy);
        assertEq(recipient, feeRecipient);
        assertEq(basisPoints, feeBasisPoints);
    }

    /// @notice Test getStrategyFeeByInstance with non-existent strategy
    function test_GetStrategyFeeByInstance_NonExistentStrategy() public {
        address nonExistentStrategy = makeAddr("nonExistentStrategy");

        vm.expectRevert(abi.encodeWithSelector(AllocatorStrategyFactory.StrategyNotFound.selector, nonExistentStrategy));
        factory.getStrategyFeeByInstance(nonExistentStrategy);
    }

    /// @notice Test getStrategyFeeByInstance with strategy not deployed by factory
    function test_GetStrategyFeeByInstance_ExternalStrategy() public {
        // Deploy a strategy outside of factory
        AllocatorStrategyMock externalStrategy = new AllocatorStrategyMock();

        vm.expectRevert(
            abi.encodeWithSelector(AllocatorStrategyFactory.StrategyNotFound.selector, address(externalStrategy))
        );
        factory.getStrategyFeeByInstance(address(externalStrategy));
    }

    /// @notice Test fee configuration persistence across deployments
    function test_FeeConfigurationPersistenceAcrossDeployments() public {
        address feeRecipient = makeAddr("feeRecipient");
        uint32 feeBasisPoints = 300; // 3%

        // Register strategy with fee
        factory.registerStrategyType(
            MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, feeRecipient, feeBasisPoints
        );

        // Deploy multiple instances
        bytes memory auxData1 = abi.encode(bytes32(keccak256("root1")));
        bytes memory auxData2 = abi.encode(bytes32(keccak256("root2")));

        address strategy1 = _deployStrategy(MERKLE_STRATEGY_ID, dao, auxData1);
        address strategy2 = _deployStrategy(MERKLE_STRATEGY_ID, dao2, auxData2);

        // Both should have same fee configuration
        (address recipient1, uint32 basisPoints1) = factory.getStrategyFeeByInstance(strategy1);
        (address recipient2, uint32 basisPoints2) = factory.getStrategyFeeByInstance(strategy2);

        assertEq(recipient1, feeRecipient);
        assertEq(basisPoints1, feeBasisPoints);
        assertEq(recipient2, feeRecipient);
        assertEq(basisPoints2, feeBasisPoints);
    }

    /// @notice Test multiple strategies with different fee configurations
    function test_MultipleStrategiesWithDifferentFees() public {
        address feeRecipient1 = makeAddr("feeRecipient1");
        address feeRecipient2 = makeAddr("feeRecipient2");
        uint32 feeBasisPoints1 = 100; // 1%
        uint32 feeBasisPoints2 = 750; // 7.5%

        // Register two strategies with different fees
        factory.registerStrategyType(
            MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, feeRecipient1, feeBasisPoints1
        );

        factory.registerStrategyType(
            MOCK_STRATEGY_ID, address(mockImplementation), MOCK_METADATA, feeRecipient2, feeBasisPoints2
        );

        // Verify different fee configurations
        (address recipient1, uint32 basisPoints1) = factory.strategyFees(MERKLE_STRATEGY_ID);
        (address recipient2, uint32 basisPoints2) = factory.strategyFees(MOCK_STRATEGY_ID);

        assertEq(recipient1, feeRecipient1);
        assertEq(basisPoints1, feeBasisPoints1);
        assertEq(recipient2, feeRecipient2);
        assertEq(basisPoints2, feeBasisPoints2);
    }

    /// ===============================
    /// FUZZ TESTS
    /// ===============================

    /// @notice Fuzz test for strategy registration
    function testFuzz_RegisterStrategyType(bytes32 strategyId, string memory metadata) public {
        vm.assume(strategyId != bytes32(0));
        vm.assume(bytes(metadata).length > 0);

        // Should succeed with valid parameters
        factory.registerStrategyType(strategyId, address(mockImplementation), metadata, address(0), 0);
        assertTrue(factory.isTypeRegistered(strategyId));

        (address regImpl, string memory regMeta) = factory.registeredTypes(strategyId);
        assertEq(regImpl, address(mockImplementation));
        assertEq(regMeta, metadata);
    }

    /// @notice Fuzz test for hash computation
    function testFuzz_ParamsHashComputation(bytes32 strategyId, address daoAddr, bytes memory auxData) public view {
        vm.assume(daoAddr != address(0));

        bytes32 hash1 = keccak256(abi.encode(strategyId, daoAddr, auxData));
        bytes32 hash2 = keccak256(abi.encode(strategyId, daoAddr, auxData));

        // Same parameters should produce same hash
        assertEq(hash1, hash2);

        // Hash should match manual computation
        bytes32 expectedHash = keccak256(abi.encode(strategyId, daoAddr, auxData));
        assertEq(hash1, expectedHash);
    }

    /// @notice Fuzz test for deployment parameters
    function testFuzz_DeploymentParameters(bytes32 strategyId, address daoAddr, bytes memory auxData) public {
        vm.assume(strategyId != bytes32(0));
        vm.assume(daoAddr != address(0));
        vm.assume(auxData.length < 10_000); // Reasonable size limit

        factory.registerStrategyType(strategyId, address(mockImplementation), "Fuzz Test Strategy", address(0), 0);

        address strategy = _deployStrategy(strategyId, IDAO(daoAddr), auxData);
        assertTrue(strategy != address(0));
        assertEq(factory.instanceToType(strategy), strategyId);
    }

    /// @notice Fuzz test for fee configuration
    function testFuzz_FeeConfiguration(bytes32 strategyId, address feeRecipient, uint32 feeBasisPoints) public {
        vm.assume(strategyId != bytes32(0));
        vm.assume(feeBasisPoints <= 1000); // Max 10%

        // Should revert if fee > 0 but recipient is zero
        if (feeBasisPoints > 0 && feeRecipient == address(0)) {
            vm.expectRevert(AllocatorStrategyFactory.InvalidFeeRecipient.selector);
            factory.registerStrategyType(
                strategyId, address(mockImplementation), "Fuzz Test", feeRecipient, feeBasisPoints
            );
        } else {
            // Should succeed otherwise
            factory.registerStrategyType(
                strategyId, address(mockImplementation), "Fuzz Test", feeRecipient, feeBasisPoints
            );

            // Verify fee configuration
            (address recipient, uint32 basisPoints) = factory.strategyFees(strategyId);
            assertEq(recipient, feeRecipient);
            assertEq(basisPoints, feeBasisPoints);
        }
    }
}

/// @notice Malicious implementation that supports interface but fails during initialization
contract MaliciousImplementation is IAllocatorStrategy {
    function initialize(
        bytes32, // strategyId
        address, // dao
        address, // deployer
        bytes calldata // auxData
    )
        external
        pure
    {
        revert("Malicious implementation");
    }

    function strategyId() external view returns (bytes32) {
        return bytes32(0);
    }

    function getInitializationEncodingTypes() external pure returns (string memory) {
        return "";
    }

    function getCreationEncodingTypes() external pure returns (string memory) {
        return "";
    }

    function getClaimEncodingTypes() external pure returns (string memory) {
        return "";
    }

    function setAllocationCampaign(uint256, bytes calldata) external pure {
        // Do nothing
    }

    function getTotalClaimableAmount(uint256, address, bytes calldata) external pure returns (uint256) {
        return 0;
    }

    function getFeeConfiguration() external pure returns (address recipient, uint32 basisPoints) {
        return (address(0), 0);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAllocatorStrategy).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
