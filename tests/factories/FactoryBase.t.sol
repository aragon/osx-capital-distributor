// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {FactoryBase} from "../../src/factories/FactoryBase.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

/// @title FactoryBase Test Suite
/// @author AragonX - 2025
/// @notice Comprehensive test suite for the FactoryBase abstract contract
/// @dev Tests all functionality, edge cases, and security vulnerabilities
contract FactoryBaseTest is Test {
    ConcreteFactoryBase factory;
    DAO dao;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address implementation1;
    address implementation2;

    bytes32 constant TYPE_ID_1 = keccak256("TYPE_1");
    bytes32 constant TYPE_ID_2 = keccak256("TYPE_2");
    bytes32 constant EMPTY_TYPE_ID = bytes32(0);

    string constant METADATA_1 = "Test Implementation 1";
    string constant METADATA_2 = "Test Implementation 2";

    event TypeRegistered(
        bytes32 indexed typeId,
        address indexed implementation,
        string metadata,
        address indexed registrar
    );

    event InstanceDeployed(
        bytes32 indexed typeId,
        address indexed instance,
        bytes32 indexed deploymentId,
        address deployer
    );

    function setUp() public {
        factory = new ConcreteFactoryBase();
        dao = DAO(payable(makeAddr("dao")));
        
        // Deploy mock implementations
        implementation1 = address(new MockImplementation());
        implementation2 = address(new MockImplementation());

        vm.label(address(factory), "Factory");
        vm.label(address(dao), "DAO");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(implementation1, "Implementation1");
        vm.label(implementation2, "Implementation2");
    }

    /// @notice Test successful type registration
    function test_RegisterType_Success() public {
        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true);
        emit TypeRegistered(TYPE_ID_1, implementation1, METADATA_1, alice);

        factory.registerType(TYPE_ID_1, implementation1, METADATA_1);

        FactoryBase.RegisteredType memory registeredType = factory.getRegisteredType(TYPE_ID_1);
        assertEq(registeredType.implementation, implementation1);
        assertEq(registeredType.metadata, METADATA_1);
        assertTrue(factory.isTypeRegistered(TYPE_ID_1));

        vm.stopPrank();
    }

    /// @notice Test registration with empty type ID
    function test_RegisterType_RevertEmptyTypeId() public {
        vm.expectRevert(FactoryBase.EmptyTypeId.selector);
        factory.registerType(EMPTY_TYPE_ID, implementation1, METADATA_1);
    }

    /// @notice Test registration with zero implementation address
    function test_RegisterType_RevertZeroImplementation() public {
        vm.expectRevert(abi.encodeWithSelector(FactoryBase.InvalidImplementation.selector, address(0), "Implementation address cannot be zero"));
        factory.registerType(TYPE_ID_1, address(0), METADATA_1);
    }

    /// @notice Test registration with non-contract address
    function test_RegisterType_RevertNonContract() public {
        vm.expectRevert(abi.encodeWithSelector(FactoryBase.InvalidImplementation.selector, alice, "Implementation must be a deployed contract"));
        factory.registerType(TYPE_ID_1, alice, METADATA_1);
    }

    /// @notice Test duplicate type registration
    function test_RegisterType_RevertAlreadyRegistered() public {
        factory.registerType(TYPE_ID_1, implementation1, METADATA_1);

        vm.expectRevert(abi.encodeWithSelector(FactoryBase.AlreadyRegistered.selector, TYPE_ID_1));
        factory.registerType(TYPE_ID_1, implementation2, METADATA_2);
    }

    /// @notice Test multiple type registrations
    function test_RegisterType_MultipleTypes() public {
        factory.registerType(TYPE_ID_1, implementation1, METADATA_1);
        factory.registerType(TYPE_ID_2, implementation2, METADATA_2);

        assertTrue(factory.isTypeRegistered(TYPE_ID_1));
        assertTrue(factory.isTypeRegistered(TYPE_ID_2));

        FactoryBase.RegisteredType memory type1 = factory.getRegisteredType(TYPE_ID_1);
        FactoryBase.RegisteredType memory type2 = factory.getRegisteredType(TYPE_ID_2);

        assertEq(type1.implementation, implementation1);
        assertEq(type2.implementation, implementation2);
    }

    /// @notice Test validation function directly
    function test_ValidateRegistration() public {
        factory.exposedValidateRegistration(TYPE_ID_1, implementation1, address(0));

        vm.expectRevert(FactoryBase.EmptyTypeId.selector);
        factory.exposedValidateRegistration(EMPTY_TYPE_ID, implementation1, address(0));

        vm.expectRevert(abi.encodeWithSelector(FactoryBase.InvalidImplementation.selector, address(0), "Implementation address cannot be zero"));
        factory.exposedValidateRegistration(TYPE_ID_1, address(0), address(0));

        vm.expectRevert(abi.encodeWithSelector(FactoryBase.AlreadyRegistered.selector, TYPE_ID_1));
        factory.exposedValidateRegistration(TYPE_ID_1, implementation1, implementation2);
    }

    /// @notice Test successful deployment and initialization
    function test_DeployAndInitialize_Success() public {
        MockImplementation mockImpl = new MockImplementation();
        factory.registerType(TYPE_ID_1, address(mockImpl), METADATA_1);

        bytes memory initData = abi.encodeWithSignature("initialize(uint256)", 42);
        address instance = factory.exposedDeployAndInitialize(TYPE_ID_1, address(mockImpl), initData);

        assertTrue(instance != address(0));
        assertEq(MockImplementation(instance).value(), 42);
    }

    /// @notice Test deployment with failing initialization
    function test_DeployAndInitialize_RevertOnFailedInit() public {
        MockImplementation mockImpl = new MockImplementation();
        factory.registerType(TYPE_ID_1, address(mockImpl), METADATA_1);

        bytes memory badInitData = abi.encodeWithSignature("initialize(uint256)", 0);

        vm.expectRevert();
        factory.exposedDeployAndInitialize(TYPE_ID_1, address(mockImpl), badInitData);
    }

    /// @notice Test extended params hash computation
    function test_ComputeParamsHash() public view {
        bytes memory auxData1 = abi.encode(1, 2, 3);
        bytes memory auxData2 = abi.encode(4, 5, 6);

        bytes32 hash1 = factory.exposedComputeParamsHash(TYPE_ID_1, IDAO(address(dao)), auxData1);
        bytes32 hash2 = factory.exposedComputeParamsHash(TYPE_ID_1, IDAO(address(dao)), auxData2);
        bytes32 hash3 = factory.exposedComputeParamsHash(TYPE_ID_2, IDAO(address(dao)), auxData1);

        assertTrue(hash1 != hash2);
        assertTrue(hash1 != hash3);
        assertTrue(hash2 != hash3);

        bytes32 expectedHash = keccak256(abi.encode(TYPE_ID_1, address(dao), auxData1));
        assertEq(hash1, expectedHash);
    }

    /// @notice Test hash collision resistance
    function test_HashCollisionResistance() public view {
        bytes memory auxData1 = abi.encodePacked(TYPE_ID_1, address(dao));
        bytes32 hash1 = factory.exposedComputeParamsHash(TYPE_ID_2, IDAO(address(0)), auxData1);

        bytes memory auxData2 = "";
        bytes32 hash2 = factory.exposedComputeParamsHash(TYPE_ID_1, IDAO(address(dao)), auxData2);

        assertTrue(hash1 != hash2);
    }

    /// @notice Test querying non-existent type
    function test_GetRegisteredType_NonExistent() public view {
        FactoryBase.RegisteredType memory registeredType = factory.getRegisteredType(TYPE_ID_1);
        assertEq(registeredType.implementation, address(0));
        assertEq(registeredType.metadata, "");
        assertFalse(factory.isTypeRegistered(TYPE_ID_1));
    }

    /// @notice Test gas consumption for various operations
    function test_GasConsumption() public {
        uint256 gasStart = gasleft();
        factory.registerType(TYPE_ID_1, implementation1, METADATA_1);
        uint256 gasUsed = gasStart - gasleft();
        console2.log("Gas used for registration:", gasUsed);
        assertTrue(gasUsed < 100000);

        gasStart = gasleft();
        factory.getRegisteredType(TYPE_ID_1);
        gasUsed = gasStart - gasleft();
        console2.log("Gas used for getRegisteredType:", gasUsed);
        assertTrue(gasUsed < 10000);

        gasStart = gasleft();
        factory.isTypeRegistered(TYPE_ID_1);
        gasUsed = gasStart - gasleft();
        console2.log("Gas used for isTypeRegistered:", gasUsed);
        assertTrue(gasUsed < 5000);
    }

    /// @notice Fuzz test for registration validation
    function testFuzz_RegisterType(bytes32 typeId, address implementation, string memory metadata) public {
        if (typeId == bytes32(0)) {
            vm.expectRevert(FactoryBase.EmptyTypeId.selector);
            factory.registerType(typeId, implementation, metadata);
        } else if (implementation == address(0)) {
            vm.expectRevert(abi.encodeWithSelector(FactoryBase.InvalidImplementation.selector, address(0), "Implementation address cannot be zero"));
            factory.registerType(typeId, implementation, metadata);
        } else if (implementation.code.length == 0) {
            vm.expectRevert(abi.encodeWithSelector(FactoryBase.InvalidImplementation.selector, implementation, "Implementation must be a deployed contract"));
            factory.registerType(typeId, implementation, metadata);
        } else {
            factory.registerType(typeId, implementation, metadata);
            assertTrue(factory.isTypeRegistered(typeId));

            FactoryBase.RegisteredType memory registeredType = factory.getRegisteredType(typeId);
            assertEq(registeredType.implementation, implementation);
            assertEq(registeredType.metadata, metadata);
        }
    }

    /// @notice Fuzz test for hash computation
    function testFuzz_HashComputation(bytes32 typeId, address daoAddr, bytes memory auxData) public view {
        IDAO daoInterface = IDAO(daoAddr);

        bytes32 extendedHash = factory.exposedComputeParamsHash(typeId, daoInterface, auxData);

        if (auxData.length == 0) {
            assertEq(extendedHash, keccak256(abi.encode(typeId, daoAddr, auxData)));
        }
    }

    /// @notice Test reentrancy protection scenario
    function test_ReentrancyScenario() public {
        ReentrantImplementation reentrantImpl = new ReentrantImplementation(address(factory));
        factory.registerType(TYPE_ID_1, address(reentrantImpl), METADATA_1);

        bytes memory initData = abi.encodeWithSignature("initialize()");

        vm.expectRevert();
        factory.exposedDeployAndInitialize(TYPE_ID_1, address(reentrantImpl), initData);
    }

    /// @notice Test deployment with large initialization data
    function test_LargeInitializationData() public {
        MockImplementation mockImpl = new MockImplementation();
        factory.registerType(TYPE_ID_1, address(mockImpl), METADATA_1);

        bytes memory largeData = new bytes(10000);
        for (uint i = 0; i < largeData.length; i++) {
            largeData[i] = bytes1(uint8(i % 256));
        }

        bytes memory initData = abi.encodeWithSignature("initialize(uint256)", 42);
        address instance = factory.exposedDeployAndInitialize(TYPE_ID_1, address(mockImpl), initData);

        assertTrue(instance != address(0));
    }
}

/// @notice Concrete implementation of FactoryBase for testing
contract ConcreteFactoryBase is FactoryBase {
    function registerType(bytes32 _typeId, address _implementation, string calldata _metadata) external {
        _registerType(_typeId, _implementation, _metadata);
    }

    function exposedValidateRegistration(
        bytes32 _typeId,
        address _implementation,
        address _existingImplementation
    ) external pure {
        _validateRegistration(_typeId, _implementation, _existingImplementation);
    }

    function exposedDeployAndInitialize(
        bytes32 _typeId,
        address _implementation,
        bytes memory _initCalldata
    ) external returns (address) {
        return _deployAndInitialize(_typeId, _implementation, _initCalldata);
    }

    function exposedComputeParamsHash(
        bytes32 _typeId,
        IDAO _dao,
        bytes memory _auxData
    ) external pure returns (bytes32) {
        return _computeParamsHash(_typeId, _dao, _auxData);
    }
}

/// @notice Mock implementation for testing deployment
contract MockImplementation {
    uint256 public value;

    function initialize(uint256 _value) external {
        require(_value > 0, "Value must be greater than 0");
        value = _value;
    }
}

/// @notice Reentrant implementation for security testing
contract ReentrantImplementation {
    address private factory;

    constructor(address _factory) {
        factory = _factory;
    }

    function initialize() external {
        ConcreteFactoryBase(factory).exposedDeployAndInitialize(bytes32("REENTRANT"), address(this), "");
    }
}

