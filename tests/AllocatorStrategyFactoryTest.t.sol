// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AllocatorStrategyFactory} from "../src/AllocatorStrategyFactory.sol";
import {FactoryBase} from "../src/FactoryBase.sol";
import {IAllocatorStrategyFactory} from "../src/interfaces/IAllocatorStrategyFactory.sol";
import {IAllocatorStrategy} from "../src/interfaces/IAllocatorStrategy.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {MerkleDistributorStrategy} from "../src/allocatorStrategies/MerkleDistributorStrategy.sol";
import {AllocatorStrategyMock} from "./mocks/AllocatorStrategyMock.sol";

/// @title AllocatorStrategyFactory Test Suite
/// @author AragonX - 2025
/// @notice Comprehensive test suite for the AllocatorStrategyFactory contract
/// @dev Tests functionality, security vulnerabilities, and edge cases
contract AllocatorStrategyFactoryTest is Test {
    AllocatorStrategyFactory factory;
    DAO dao;
    DAO dao2;
    
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
    event StrategyRetrieved(bytes32 indexed strategyId, address indexed strategy, bytes32 indexed deploymentId);
    event TypeRegistered(bytes32 indexed typeId, address indexed implementation, string metadata, address indexed registrar);
    event InstanceDeployed(bytes32 indexed typeId, address indexed instance, bytes32 indexed deploymentId, address deployer);

    function setUp() public {
        factory = new AllocatorStrategyFactory();
        dao = DAO(payable(makeAddr("dao")));
        dao2 = DAO(payable(makeAddr("dao2")));
        
        // Deploy strategy implementations
        merkleImplementation = new MerkleDistributorStrategy();
        mockImplementation = new AllocatorStrategyMock();
        maliciousImplementation = address(new MaliciousImplementation());
        
        vm.label(address(factory), "Factory");
        vm.label(address(dao), "DAO");
        vm.label(address(dao2), "DAO2");
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
        vm.startPrank(alice);
        
        vm.expectEmit(true, true, false, true);
        emit TypeRegistered(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA, alice);
        
        vm.expectEmit(true, true, false, true);
        emit StrategyTypeRegistered(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA);
        
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA);
        
        FactoryBase.RegisteredType memory registeredType = factory.getRegisteredType(MERKLE_STRATEGY_ID);
        assertEq(registeredType.implementation, address(merkleImplementation));
        assertEq(registeredType.metadata, MERKLE_METADATA);
        assertTrue(factory.isTypeRegistered(MERKLE_STRATEGY_ID));
        
        vm.stopPrank();
    }

    /// @notice Test multiple strategy type registrations
    function test_RegisterStrategyType_Multiple() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA);
        factory.registerStrategyType(MOCK_STRATEGY_ID, address(mockImplementation), MOCK_METADATA);
        
        assertTrue(factory.isTypeRegistered(MERKLE_STRATEGY_ID));
        assertTrue(factory.isTypeRegistered(MOCK_STRATEGY_ID));
        
        FactoryBase.RegisteredType memory merkleType = factory.getRegisteredType(MERKLE_STRATEGY_ID);
        FactoryBase.RegisteredType memory mockType = factory.getRegisteredType(MOCK_STRATEGY_ID);
        
        assertEq(merkleType.implementation, address(merkleImplementation));
        assertEq(mockType.implementation, address(mockImplementation));
    }

    /// @notice Test registration with empty strategy ID
    function test_RegisterStrategyType_RevertEmptyId() public {
        vm.expectRevert(FactoryBase.EmptyTypeId.selector);
        factory.registerStrategyType(EMPTY_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA);
    }

    /// @notice Test registration with zero implementation address
    function test_RegisterStrategyType_RevertZeroImplementation() public {
        vm.expectRevert(abi.encodeWithSelector(FactoryBase.InvalidImplementation.selector, address(0), "Implementation address cannot be zero"));
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(0), MERKLE_METADATA);
    }

    /// @notice Test registration with non-contract address
    function test_RegisterStrategyType_RevertNonContract() public {
        vm.expectRevert(abi.encodeWithSelector(FactoryBase.InvalidImplementation.selector, alice, "Implementation must be a deployed contract"));
        factory.registerStrategyType(MERKLE_STRATEGY_ID, alice, MERKLE_METADATA);
    }

    /// @notice Test duplicate strategy type registration
    function test_RegisterStrategyType_RevertAlreadyRegistered() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA);
        
        vm.expectRevert(abi.encodeWithSelector(FactoryBase.AlreadyRegistered.selector, MERKLE_STRATEGY_ID));
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(mockImplementation), MOCK_METADATA);
    }

    /// ===============================
    /// STRATEGY DEPLOYMENT TESTS
    /// ===============================

    /// @notice Test successful strategy deployment
    function test_DeployStrategy_Success() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA);
        
        bytes memory auxData = abi.encode(bytes32(keccak256("test-merkle-root")));
        
        vm.expectEmit(true, false, false, false);
        emit InstanceDeployed(MERKLE_STRATEGY_ID, address(0), bytes32(0), address(this));
        
        vm.expectEmit(true, false, false, false);
        emit StrategyDeployed(MERKLE_STRATEGY_ID, address(0));
        
        address strategy = factory.deployStrategy(MERKLE_STRATEGY_ID, dao, auxData);
        
        assertTrue(strategy != address(0));
        assertEq(factory.instanceToType(strategy), MERKLE_STRATEGY_ID);
        
        // Verify strategy was properly initialized
        assertEq(IAllocatorStrategy(strategy).strategyTypeId(), MERKLE_STRATEGY_ID);
    }

    /// @notice Test deployment with non-existent strategy type
    function test_DeployStrategy_RevertTypeNotFound() public {
        bytes memory auxData = abi.encode(bytes32(keccak256("test-data")));
        
        vm.expectRevert(abi.encodeWithSelector(FactoryBase.TypeNotFound.selector, MERKLE_STRATEGY_ID));
        factory.deployStrategy(MERKLE_STRATEGY_ID, dao, auxData);
    }

    /// @notice Test deployment with duplicate parameters
    function test_DeployStrategy_RevertInstanceAlreadyDeployed() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA);
        
        bytes memory auxData = abi.encode(bytes32(keccak256("test-merkle-root")));
        
        // First deployment should succeed
        address strategy1 = factory.deployStrategy(MERKLE_STRATEGY_ID, dao, auxData);
        assertTrue(strategy1 != address(0));
        
        // Second deployment with same parameters should revert
        bytes32 deploymentId = keccak256(abi.encode(MERKLE_STRATEGY_ID, address(dao), auxData));
        vm.expectRevert(abi.encodeWithSelector(FactoryBase.InstanceAlreadyDeployed.selector, deploymentId, strategy1));
        factory.deployStrategy(MERKLE_STRATEGY_ID, dao, auxData);
    }

    /// @notice Test deployment with different auxiliary data creates different instances
    function test_DeployStrategy_DifferentAuxDataCreatesNewInstance() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA);
        
        bytes memory auxData1 = abi.encode(bytes32(keccak256("root1")));
        bytes memory auxData2 = abi.encode(bytes32(keccak256("root2")));
        
        address strategy1 = factory.deployStrategy(MERKLE_STRATEGY_ID, dao, auxData1);
        address strategy2 = factory.deployStrategy(MERKLE_STRATEGY_ID, dao, auxData2);
        
        assertTrue(strategy1 != strategy2);
        assertEq(factory.instanceToType(strategy1), MERKLE_STRATEGY_ID);
        assertEq(factory.instanceToType(strategy2), MERKLE_STRATEGY_ID);
    }

    /// @notice Test deployment with different DAOs creates different instances
    function test_DeployStrategy_DifferentDAOCreatesNewInstance() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA);
        
        bytes memory auxData = abi.encode(bytes32(keccak256("test-merkle-root")));
        
        address strategy1 = factory.deployStrategy(MERKLE_STRATEGY_ID, dao, auxData);
        address strategy2 = factory.deployStrategy(MERKLE_STRATEGY_ID, dao2, auxData);
        
        assertTrue(strategy1 != strategy2);
        assertEq(factory.instanceToType(strategy1), MERKLE_STRATEGY_ID);
        assertEq(factory.instanceToType(strategy2), MERKLE_STRATEGY_ID);
    }

    /// =======================================
    /// GET OR DEPLOY STRATEGY TESTS
    /// =======================================

    /// @notice Test getOrDeployStrategy returns existing instance
    function test_GetOrDeployStrategy_ReturnsExisting() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA);
        
        bytes memory auxData = abi.encode(bytes32(keccak256("test-merkle-root")));
        
        address strategy1 = factory.deployStrategy(MERKLE_STRATEGY_ID, dao, auxData);
        
        bytes32 expectedDeploymentId = keccak256(abi.encode(MERKLE_STRATEGY_ID, address(dao), auxData));
        
        vm.expectEmit(true, true, true, false);
        emit StrategyRetrieved(MERKLE_STRATEGY_ID, strategy1, expectedDeploymentId);
        
        address strategy2 = factory.getOrDeployStrategy(MERKLE_STRATEGY_ID, dao, auxData);
        
        assertEq(strategy1, strategy2);
    }

    /// @notice Test getOrDeployStrategy deploys new instance when none exists
    function test_GetOrDeployStrategy_DeploysNew() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA);
        
        bytes memory auxData = abi.encode(bytes32(keccak256("test-merkle-root")));
        
        address strategy = factory.getOrDeployStrategy(MERKLE_STRATEGY_ID, dao, auxData);
        
        assertTrue(strategy != address(0));
        assertEq(factory.instanceToType(strategy), MERKLE_STRATEGY_ID);
    }

    /// ===============================
    /// INSTANCE EXISTS TESTS
    /// ===============================

    /// @notice Test instanceExists returns correct values
    function test_InstanceExists() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA);
        
        bytes memory auxData = abi.encode(bytes32(keccak256("test-merkle-root")));
        
        // Should not exist initially
        (bool exists, address strategy) = factory.instanceExists(MERKLE_STRATEGY_ID, dao, auxData);
        assertFalse(exists);
        assertEq(strategy, address(0));
        
        // Deploy strategy
        address deployedStrategy = factory.deployStrategy(MERKLE_STRATEGY_ID, dao, auxData);
        
        // Should exist after deployment
        (exists, strategy) = factory.instanceExists(MERKLE_STRATEGY_ID, dao, auxData);
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
        factory.registerStrategyType(MALICIOUS_STRATEGY_ID, maliciousImplementation, MALICIOUS_METADATA);
        assertTrue(factory.isTypeRegistered(MALICIOUS_STRATEGY_ID));
    }

    /// @notice Test malicious implementation deployment failure
    function test_Security_MaliciousImplementationDeploymentFailure() public {
        factory.registerStrategyType(MALICIOUS_STRATEGY_ID, maliciousImplementation, MALICIOUS_METADATA);
        
        bytes memory auxData = abi.encode(bytes32(keccak256("malicious-data")));
        
        // Deployment should fail due to malicious implementation's initialize function
        vm.expectRevert();
        factory.deployStrategy(MALICIOUS_STRATEGY_ID, dao, auxData);
    }

    /// @notice Test access control - anyone can register strategy types (no access control)
    function test_Security_NoAccessControlOnRegistration() public {
        vm.startPrank(maliciousActor);
        
        // Should succeed - no access control on registration
        factory.registerStrategyType(MALICIOUS_STRATEGY_ID, address(mockImplementation), MALICIOUS_METADATA);
        assertTrue(factory.isTypeRegistered(MALICIOUS_STRATEGY_ID));
        
        vm.stopPrank();
    }

    /// @notice Test large auxiliary data handling
    function test_Security_LargeAuxiliaryData() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA);
        
        // Create very large auxiliary data (10KB)
        bytes memory largeAuxData = new bytes(10240);
        for (uint i = 0; i < largeAuxData.length; i++) {
            largeAuxData[i] = bytes1(uint8(i % 256));
        }
        
        // Should handle large data without issues
        address strategy = factory.deployStrategy(MERKLE_STRATEGY_ID, dao, largeAuxData);
        assertTrue(strategy != address(0));
    }

    /// @notice Test initialization data injection
    function test_Security_InitializationDataInjection() public {
        factory.registerStrategyType(MOCK_STRATEGY_ID, address(mockImplementation), MOCK_METADATA);
        
        // Attempt to inject malicious data through auxData
        bytes memory maliciousAuxData = abi.encode(
            bytes32(keccak256("malicious")),
            address(maliciousActor),
            "injected data"
        );
        
        // Deployment should succeed but malicious data should be contained
        address strategy = factory.deployStrategy(MOCK_STRATEGY_ID, dao, maliciousAuxData);
        assertTrue(strategy != address(0));
        
        // Verify the strategy was initialized with correct parameters
        assertEq(IAllocatorStrategy(strategy).strategyTypeId(), MOCK_STRATEGY_ID);
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
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA);
        gasUsed = gasStart - gasleft();
        console2.log("Gas used for strategy registration:", gasUsed);
        assertTrue(gasUsed < 150000);
        
        // Deployment gas test
        bytes memory auxData = abi.encode(bytes32(keccak256("test-merkle-root")));
        gasStart = gasleft();
        factory.deployStrategy(MERKLE_STRATEGY_ID, dao, auxData);
        gasUsed = gasStart - gasleft();
        console2.log("Gas used for strategy deployment:", gasUsed);
        assertTrue(gasUsed < 200000);
        
        // Instance exists check gas test
        gasStart = gasleft();
        factory.instanceExists(MERKLE_STRATEGY_ID, dao, auxData);
        gasUsed = gasStart - gasleft();
        console2.log("Gas used for instanceExists:", gasUsed);
        assertTrue(gasUsed < 10000);
    }

    /// ===============================
    /// EDGE CASE TESTS
    /// ===============================

    /// @notice Test deployment with empty auxiliary data
    function test_EdgeCase_EmptyAuxiliaryData() public {
        factory.registerStrategyType(MOCK_STRATEGY_ID, address(mockImplementation), MOCK_METADATA);
        
        bytes memory emptyAuxData = "";
        address strategy = factory.deployStrategy(MOCK_STRATEGY_ID, dao, emptyAuxData);
        
        assertTrue(strategy != address(0));
        assertEq(factory.instanceToType(strategy), MOCK_STRATEGY_ID);
    }

    /// @notice Test deployment with maximum auxiliary data size
    function test_EdgeCase_MaxAuxiliaryData() public {
        factory.registerStrategyType(MOCK_STRATEGY_ID, address(mockImplementation), MOCK_METADATA);
        
        // Create maximum reasonable auxiliary data (64KB)
        bytes memory maxAuxData = new bytes(65536);
        for (uint i = 0; i < maxAuxData.length; i++) {
            maxAuxData[i] = bytes1(uint8(i % 256));
        }
        
        address strategy = factory.deployStrategy(MOCK_STRATEGY_ID, dao, maxAuxData);
        assertTrue(strategy != address(0));
    }

    /// @notice Test multiple concurrent deployments
    function test_EdgeCase_ConcurrentDeployments() public {
        factory.registerStrategyType(MERKLE_STRATEGY_ID, address(merkleImplementation), MERKLE_METADATA);
        factory.registerStrategyType(MOCK_STRATEGY_ID, address(mockImplementation), MOCK_METADATA);
        
        bytes memory auxData1 = abi.encode(bytes32(keccak256("concurrent1")));
        bytes memory auxData2 = abi.encode(bytes32(keccak256("concurrent2")));
        
        address strategy1 = factory.deployStrategy(MERKLE_STRATEGY_ID, dao, auxData1);
        address strategy2 = factory.deployStrategy(MOCK_STRATEGY_ID, dao, auxData2);
        address strategy3 = factory.deployStrategy(MERKLE_STRATEGY_ID, dao2, auxData1);
        
        assertTrue(strategy1 != strategy2);
        assertTrue(strategy1 != strategy3);
        assertTrue(strategy2 != strategy3);
        
        assertEq(factory.instanceToType(strategy1), MERKLE_STRATEGY_ID);
        assertEq(factory.instanceToType(strategy2), MOCK_STRATEGY_ID);
        assertEq(factory.instanceToType(strategy3), MERKLE_STRATEGY_ID);
    }

    /// ===============================
    /// FUZZ TESTS
    /// ===============================

    /// @notice Fuzz test for strategy registration
    function testFuzz_RegisterStrategyType(bytes32 strategyId, string memory metadata) public {
        vm.assume(strategyId != bytes32(0));
        vm.assume(bytes(metadata).length > 0);
        
        // Should succeed with valid parameters
        factory.registerStrategyType(strategyId, address(mockImplementation), metadata);
        assertTrue(factory.isTypeRegistered(strategyId));
        
        FactoryBase.RegisteredType memory registeredType = factory.getRegisteredType(strategyId);
        assertEq(registeredType.implementation, address(mockImplementation));
        assertEq(registeredType.metadata, metadata);
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
        vm.assume(auxData.length < 10000); // Reasonable size limit
        
        factory.registerStrategyType(strategyId, address(mockImplementation), "Fuzz Test Strategy");
        
        address strategy = factory.deployStrategy(strategyId, IDAO(daoAddr), auxData);
        assertTrue(strategy != address(0));
        assertEq(factory.instanceToType(strategy), strategyId);
    }
}

/// @notice Malicious implementation that supports interface but fails during initialization
contract MaliciousImplementation is IAllocatorStrategy {
    function initialize(
        bytes32, // strategyTypeId
        address, // dao
        address, // deployer
        bytes calldata // auxData
    ) external pure {
        revert("Malicious implementation");
    }

    function strategyTypeId() external view returns (bytes32) {
        return bytes32(0);
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

    function getClaimeableAmount(uint256, address, bytes calldata) external pure returns (uint256) {
        return 0;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAllocatorStrategy).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}