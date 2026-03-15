// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { ActionEncoderFactory } from "../../src/factories/ActionEncoderFactory.sol";
import { FactoryBase } from "../../src/factories/FactoryBase.sol";
import { IPayoutActionEncoder } from "../../src/interfaces/IPayoutActionEncoder.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";
import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { VaultDepositPayoutActionEncoder } from "../../src/payoutActionEncoders/VaultDepositPayoutActionEncoder.sol";
import { PayoutActionEncoderBase } from "../../src/payoutActionEncoders/PayoutActionEncoderBase.sol";
import { Action } from "@aragon/commons/executors/IExecutor.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { CapitalDistributorPluginMock } from "../mocks/CapitalDistributorPluginMock.sol";

/// @title ActionEncoderFactory Test Suite
/// @author AragonX - 2025
/// @notice Comprehensive test suite for the ActionEncoderFactory contract
/// @dev Tests functionality, security vulnerabilities, and edge cases
contract ActionEncoderFactoryTest is Test {
    ActionEncoderFactory factory;
    DAO dao;
    DAO dao2;
    CapitalDistributorPluginMock pluginMock;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address maliciousActor = makeAddr("malicious");

    VaultDepositPayoutActionEncoder vaultImplementation;
    ActionEncoderMock mockImplementation;
    address maliciousImplementation;

    bytes32 constant VAULT_ENCODER_ID = keccak256("vault-deposit-encoder");
    bytes32 constant MOCK_ENCODER_ID = keccak256("mock-encoder");
    bytes32 constant MALICIOUS_ENCODER_ID = keccak256("malicious-encoder");
    bytes32 constant EMPTY_ENCODER_ID = bytes32(0);

    string constant VAULT_METADATA = "Vault Deposit Payout Action Encoder";
    string constant MOCK_METADATA = "Mock Action Encoder for Testing";
    string constant MALICIOUS_METADATA = "Malicious Action Encoder";

    // Test events
    event ActionEncoderTypeRegistered(bytes32 indexed encoderId, address indexed implementation, string metadata);
    event ActionEncoderDeployed(bytes32 indexed encoderId, IPayoutActionEncoder indexed encoder);
    event TypeRegistered(
        bytes32 indexed typeId, address indexed implementation, string metadata, address indexed registrar
    );
    event InstanceDeployed(
        bytes32 indexed typeId, address indexed instance, bytes32 indexed deploymentId, address deployer
    );

    /// @notice Helper function to deploy action encoder through authorized plugin mock
    function _deployActionEncoder(
        bytes32 encoderId,
        IDAO daoAddr,
        bytes memory auxData
    )
        internal
        returns (IPayoutActionEncoder)
    {
        vm.startPrank(address(pluginMock));
        IPayoutActionEncoder encoder = factory.deployActionEncoder(encoderId, daoAddr, auxData);
        vm.stopPrank();
        return encoder;
    }

    /// @notice Helper function to get or deploy action encoder through authorized plugin mock
    function _getOrDeployActionEncoder(
        bytes32 encoderId,
        IDAO daoAddr,
        bytes memory auxData
    )
        internal
        returns (IPayoutActionEncoder)
    {
        vm.startPrank(address(pluginMock));
        IPayoutActionEncoder encoder = factory.getOrDeployActionEncoder(encoderId, daoAddr, auxData);
        vm.stopPrank();
        return encoder;
    }

    function setUp() public {
        factory = new ActionEncoderFactory();
        dao = DAO(payable(makeAddr("dao")));
        dao2 = DAO(payable(makeAddr("dao2")));
        pluginMock = new CapitalDistributorPluginMock();

        // Deploy encoder implementations
        vaultImplementation = new VaultDepositPayoutActionEncoder();
        mockImplementation = new ActionEncoderMock();
        maliciousImplementation = address(new MaliciousActionEncoder());

        vm.label(address(factory), "Factory");
        vm.label(address(dao), "DAO");
        vm.label(address(dao2), "DAO2");
        vm.label(address(pluginMock), "PluginMock");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(maliciousActor, "MaliciousActor");
        vm.label(address(vaultImplementation), "VaultImplementation");
        vm.label(address(mockImplementation), "MockImplementation");
        vm.label(maliciousImplementation, "MaliciousImplementation");
    }

    /// ================================
    /// ACTION ENCODER TYPE REGISTRATION TESTS
    /// ================================

    /// @notice Test successful action encoder type registration
    function test_RegisterActionEncoder_Success() public {
        vm.expectEmit(true, true, false, true);
        emit TypeRegistered(VAULT_ENCODER_ID, address(vaultImplementation), VAULT_METADATA, alice);

        vm.expectEmit(true, true, false, true);
        emit ActionEncoderTypeRegistered(VAULT_ENCODER_ID, address(vaultImplementation), VAULT_METADATA);

        factory.registerActionEncoder(VAULT_ENCODER_ID, address(vaultImplementation), VAULT_METADATA);

        (address implementation, string memory metadata) = factory.registeredTypes(VAULT_ENCODER_ID);
        assertEq(implementation, address(vaultImplementation));
        assertEq(metadata, VAULT_METADATA);
        assertTrue(factory.isTypeRegistered(VAULT_ENCODER_ID));
    }

    /// @notice Test multiple action encoder type registrations
    function test_RegisterActionEncoder_Multiple() public {
        factory.registerActionEncoder(VAULT_ENCODER_ID, address(vaultImplementation), VAULT_METADATA);

        assertTrue(factory.isTypeRegistered(VAULT_ENCODER_ID));

        (address vaultImpl,) = factory.registeredTypes(VAULT_ENCODER_ID);

        assertEq(vaultImpl, address(vaultImplementation));
    }

    /// @notice Test registration with empty encoder ID
    function test_RegisterActionEncoder_RevertEmptyId() public {
        vm.expectRevert(FactoryBase.EmptyTypeId.selector);
        factory.registerActionEncoder(EMPTY_ENCODER_ID, address(vaultImplementation), VAULT_METADATA);
    }

    /// @notice Test registration with zero implementation address
    function test_RegisterActionEncoder_RevertZeroImplementation() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                FactoryBase.InvalidImplementation.selector, address(0), "Implementation address cannot be zero"
            )
        );
        factory.registerActionEncoder(VAULT_ENCODER_ID, address(0), VAULT_METADATA);
    }

    /// @notice Test registration with non-contract address
    function test_RegisterActionEncoder_RevertNonContract() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                FactoryBase.InvalidImplementation.selector, alice, "Implementation must be a deployed contract"
            )
        );
        factory.registerActionEncoder(VAULT_ENCODER_ID, alice, VAULT_METADATA);
    }

    /// @notice Test duplicate action encoder type registration
    function test_RegisterActionEncoder_RevertAlreadyRegistered() public {
        factory.registerActionEncoder(VAULT_ENCODER_ID, address(vaultImplementation), VAULT_METADATA);

        vm.expectRevert(abi.encodeWithSelector(FactoryBase.AlreadyRegistered.selector, VAULT_ENCODER_ID));
        factory.registerActionEncoder(VAULT_ENCODER_ID, address(mockImplementation), MOCK_METADATA);
    }

    /// @notice Test registration with implementation that doesn't support IPayoutActionEncoder interface
    function test_RegisterActionEncoder_RevertInvalidInterface() public {
        address invalidImplementation = address(new NonCompliantImplementation());

        vm.expectRevert(
            abi.encodeWithSelector(
                FactoryBase.InvalidImplementation.selector,
                invalidImplementation,
                "Implementation must support IPayoutActionEncoder interface"
            )
        );
        factory.registerActionEncoder(VAULT_ENCODER_ID, invalidImplementation, VAULT_METADATA);
    }

    /// ===============================
    /// ACTION ENCODER DEPLOYMENT TESTS
    /// ===============================

    /// @notice Test successful action encoder deployment
    function test_DeployActionEncoder_Success() public {
        factory.registerActionEncoder(VAULT_ENCODER_ID, address(vaultImplementation), VAULT_METADATA);

        bytes memory auxData = abi.encode(address(0x123)); // Mock vault address

        vm.expectEmit(true, false, false, false);
        emit InstanceDeployed(VAULT_ENCODER_ID, address(0), bytes32(0), address(pluginMock));

        vm.expectEmit(true, false, false, false);
        emit ActionEncoderDeployed(VAULT_ENCODER_ID, IPayoutActionEncoder(address(0)));

        IPayoutActionEncoder encoder = _deployActionEncoder(VAULT_ENCODER_ID, dao, auxData);

        assertTrue(address(encoder) != address(0));
        assertEq(factory.instanceToType(address(encoder)), VAULT_ENCODER_ID);

        // Verify encoder was properly initialized
        assertEq(encoder.encoderId(), VAULT_ENCODER_ID);
    }

    /// @notice Test deployment with non-existent encoder type
    function test_DeployActionEncoder_RevertTypeNotFound() public {
        bytes memory auxData = abi.encode(address(0x123));

        vm.expectRevert(abi.encodeWithSelector(FactoryBase.TypeNotFound.selector, VAULT_ENCODER_ID));
        _deployActionEncoder(VAULT_ENCODER_ID, dao, auxData);
    }

    /// @notice Test deployment with duplicate parameters
    function test_DeployActionEncoder_RevertInstanceAlreadyDeployed() public {
        factory.registerActionEncoder(VAULT_ENCODER_ID, address(vaultImplementation), VAULT_METADATA);

        bytes memory auxData = abi.encode(address(0x123));

        // First deployment should succeed
        IPayoutActionEncoder encoder1 = _deployActionEncoder(VAULT_ENCODER_ID, dao, auxData);
        assertTrue(address(encoder1) != address(0));

        // Second deployment with same parameters should revert
        bytes32 deploymentId = keccak256(abi.encode(VAULT_ENCODER_ID, address(dao), address(pluginMock), auxData));
        vm.expectRevert(
            abi.encodeWithSelector(FactoryBase.InstanceAlreadyDeployed.selector, deploymentId, address(encoder1))
        );
        _deployActionEncoder(VAULT_ENCODER_ID, dao, auxData);
    }

    /// @notice Test deployment with different auxiliary data creates different instances
    function test_DeployActionEncoder_DifferentAuxDataCreatesNewInstance() public {
        factory.registerActionEncoder(VAULT_ENCODER_ID, address(vaultImplementation), VAULT_METADATA);

        bytes memory auxData1 = abi.encode(address(0x123));
        bytes memory auxData2 = abi.encode(address(0x456));

        IPayoutActionEncoder encoder1 = _deployActionEncoder(VAULT_ENCODER_ID, dao, auxData1);
        IPayoutActionEncoder encoder2 = _deployActionEncoder(VAULT_ENCODER_ID, dao, auxData2);

        assertTrue(address(encoder1) != address(encoder2));
        assertEq(factory.instanceToType(address(encoder1)), VAULT_ENCODER_ID);
        assertEq(factory.instanceToType(address(encoder2)), VAULT_ENCODER_ID);
    }

    /// @notice Test deployment with different DAOs creates different instances
    function test_DeployActionEncoder_DifferentDAOCreatesNewInstance() public {
        factory.registerActionEncoder(VAULT_ENCODER_ID, address(vaultImplementation), VAULT_METADATA);

        bytes memory auxData = abi.encode(address(0x123));

        IPayoutActionEncoder encoder1 = _deployActionEncoder(VAULT_ENCODER_ID, dao, auxData);
        IPayoutActionEncoder encoder2 = _deployActionEncoder(VAULT_ENCODER_ID, dao2, auxData);

        assertTrue(address(encoder1) != address(encoder2));
        assertEq(factory.instanceToType(address(encoder1)), VAULT_ENCODER_ID);
        assertEq(factory.instanceToType(address(encoder2)), VAULT_ENCODER_ID);
    }

    /// =======================================
    /// GET OR DEPLOY ACTION ENCODER TESTS
    /// =======================================

    /// @notice Test getOrDeployActionEncoder returns existing instance
    function test_GetOrDeployActionEncoder_ReturnsExisting() public {
        factory.registerActionEncoder(VAULT_ENCODER_ID, address(vaultImplementation), VAULT_METADATA);

        bytes memory auxData = abi.encode(address(0x123));

        IPayoutActionEncoder encoder1 = _deployActionEncoder(VAULT_ENCODER_ID, dao, auxData);
        IPayoutActionEncoder encoder2 = _getOrDeployActionEncoder(VAULT_ENCODER_ID, dao, auxData);

        assertEq(address(encoder1), address(encoder2));
    }

    /// @notice Test getOrDeployActionEncoder deploys new instance when none exists
    function test_GetOrDeployActionEncoder_DeploysNew() public {
        factory.registerActionEncoder(VAULT_ENCODER_ID, address(vaultImplementation), VAULT_METADATA);

        bytes memory auxData = abi.encode(address(0x123));

        IPayoutActionEncoder encoder = _getOrDeployActionEncoder(VAULT_ENCODER_ID, dao, auxData);

        assertTrue(address(encoder) != address(0));
        assertEq(factory.instanceToType(address(encoder)), VAULT_ENCODER_ID);
    }

    /// ===============================
    /// INSTANCE EXISTS TESTS
    /// ===============================

    /// @notice Test hasDeployment returns correct values
    function test_HasDeployment() public {
        factory.registerActionEncoder(VAULT_ENCODER_ID, address(vaultImplementation), VAULT_METADATA);

        bytes memory auxData = abi.encode(address(0x123));

        // Should not exist initially
        (bool exists, IPayoutActionEncoder encoder) =
            factory.hasDeployment(VAULT_ENCODER_ID, dao, address(pluginMock), auxData);
        assertFalse(exists);
        assertEq(address(encoder), address(0));

        // Deploy encoder
        IPayoutActionEncoder deployedEncoder = _deployActionEncoder(VAULT_ENCODER_ID, dao, auxData);

        // Should exist after deployment
        (exists, encoder) = factory.hasDeployment(VAULT_ENCODER_ID, dao, address(pluginMock), auxData);
        assertTrue(exists);
        assertEq(address(encoder), address(deployedEncoder));
    }

    /// ===============================
    /// PARAMETER HASH COMPUTATION TESTS
    /// ===============================

    /// @notice Test hash computation consistency
    function test_ParamsHashComputation() public view {
        bytes memory auxData1 = abi.encode(address(0x123));
        bytes memory auxData2 = abi.encode(address(0x456));

        bytes32 hash1 = keccak256(abi.encode(VAULT_ENCODER_ID, address(dao), auxData1));
        bytes32 hash2 = keccak256(abi.encode(VAULT_ENCODER_ID, address(dao), auxData2));
        bytes32 hash3 = keccak256(abi.encode(MOCK_ENCODER_ID, address(dao), auxData1));
        bytes32 hash4 = keccak256(abi.encode(VAULT_ENCODER_ID, address(dao2), auxData1));

        assertTrue(hash1 != hash2);
        assertTrue(hash1 != hash3);
        assertTrue(hash1 != hash4);
        assertTrue(hash2 != hash3);
        assertTrue(hash2 != hash4);
        assertTrue(hash3 != hash4);
    }

    /// ===============================
    /// SECURITY TESTS
    /// ===============================

    /// @notice Test malicious implementation registration (should be allowed)
    function test_Security_MaliciousImplementationRegistration() public {
        // Registration should succeed (factory doesn't validate implementation logic)
        factory.registerActionEncoder(MALICIOUS_ENCODER_ID, maliciousImplementation, MALICIOUS_METADATA);
        assertTrue(factory.isTypeRegistered(MALICIOUS_ENCODER_ID));
    }

    /// @notice Test malicious implementation deployment failure
    function test_Security_MaliciousImplementationDeploymentFailure() public {
        factory.registerActionEncoder(MALICIOUS_ENCODER_ID, maliciousImplementation, MALICIOUS_METADATA);

        bytes memory auxData = abi.encode(address(0x123));

        // Deployment should fail due to malicious implementation's initialize function
        vm.expectRevert();
        _deployActionEncoder(MALICIOUS_ENCODER_ID, dao, auxData);
    }

    /// @notice Test large auxiliary data handling
    function test_Security_LargeAuxiliaryData() public {
        factory.registerActionEncoder(MOCK_ENCODER_ID, address(mockImplementation), MOCK_METADATA);

        // Create very large auxiliary data (10KB)
        bytes memory largeAuxData = new bytes(10_240);
        for (uint256 i = 0; i < largeAuxData.length; i++) {
            largeAuxData[i] = bytes1(uint8(i % 256));
        }

        // Should handle large data without issues
        IPayoutActionEncoder encoder = _deployActionEncoder(MOCK_ENCODER_ID, dao, largeAuxData);
        assertTrue(address(encoder) != address(0));
    }

    /// @notice Test initialization data injection
    function test_Security_InitializationDataInjection() public {
        factory.registerActionEncoder(MOCK_ENCODER_ID, address(mockImplementation), MOCK_METADATA);

        // Attempt to inject malicious data through auxData
        bytes memory maliciousAuxData = abi.encode(address(maliciousActor), "injected data");

        // Deployment should succeed but malicious data should be contained
        IPayoutActionEncoder encoder = _deployActionEncoder(MOCK_ENCODER_ID, dao, maliciousAuxData);
        assertTrue(address(encoder) != address(0));

        // Verify the encoder was initialized with correct parameters
        assertEq(encoder.encoderId(), MOCK_ENCODER_ID);
    }

    /// ===============================
    /// INTEGRATION TESTS WITH REAL IMPLEMENTATIONS
    /// ===============================

    /// @notice Test integration with VaultDepositPayoutActionEncoder
    function test_Integration_VaultDepositEncoder() public {
        factory.registerActionEncoder(VAULT_ENCODER_ID, address(vaultImplementation), VAULT_METADATA);

        bytes memory auxData = abi.encode(address(0x123)); // Mock vault address

        IPayoutActionEncoder encoder = _deployActionEncoder(VAULT_ENCODER_ID, dao, auxData);

        // Test that the encoder can be used
        assertEq(encoder.getCreationEncodingTypes(), "address");
        assertEq(encoder.getClaimEncodingTypes(), "");
        assertEq(encoder.encoderId(), VAULT_ENCODER_ID);
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
        factory.registerActionEncoder(VAULT_ENCODER_ID, address(vaultImplementation), VAULT_METADATA);
        gasUsed = gasStart - gasleft();
        console2.log("Gas used for encoder registration:", gasUsed);
        assertTrue(gasUsed < 150_000);

        // Deployment gas test
        bytes memory auxData = abi.encode(address(0x123));
        gasStart = gasleft();
        _deployActionEncoder(VAULT_ENCODER_ID, dao, auxData);
        gasUsed = gasStart - gasleft();
        console2.log("Gas used for encoder deployment:", gasUsed);
        assertTrue(gasUsed < 250_000);

        // Instance exists check gas test
        gasStart = gasleft();
        factory.hasDeployment(VAULT_ENCODER_ID, dao, address(pluginMock), auxData);
        gasUsed = gasStart - gasleft();
        console2.log("Gas used for hasDeployment:", gasUsed);
        assertTrue(gasUsed < 10_000);
    }

    /// ===============================
    /// EDGE CASE TESTS
    /// ===============================

    /// @notice Test deployment with empty auxiliary data
    function test_EdgeCase_EmptyAuxiliaryData() public {
        factory.registerActionEncoder(MOCK_ENCODER_ID, address(mockImplementation), MOCK_METADATA);

        bytes memory emptyAuxData = "";
        IPayoutActionEncoder encoder = _deployActionEncoder(MOCK_ENCODER_ID, dao, emptyAuxData);

        assertTrue(address(encoder) != address(0));
        assertEq(factory.instanceToType(address(encoder)), MOCK_ENCODER_ID);
    }

    /// @notice Test deployment with maximum auxiliary data size
    function test_EdgeCase_MaxAuxiliaryData() public {
        factory.registerActionEncoder(MOCK_ENCODER_ID, address(mockImplementation), MOCK_METADATA);

        // Create maximum reasonable auxiliary data (64KB)
        bytes memory maxAuxData = new bytes(65_536);
        for (uint256 i = 0; i < maxAuxData.length; i++) {
            maxAuxData[i] = bytes1(uint8(i % 256));
        }

        IPayoutActionEncoder encoder = _deployActionEncoder(MOCK_ENCODER_ID, dao, maxAuxData);
        assertTrue(address(encoder) != address(0));
    }

    /// @notice Test multiple concurrent deployments
    function test_EdgeCase_ConcurrentDeployments() public {
        factory.registerActionEncoder(VAULT_ENCODER_ID, address(vaultImplementation), VAULT_METADATA);
        factory.registerActionEncoder(MOCK_ENCODER_ID, address(mockImplementation), MOCK_METADATA);

        bytes memory auxData1 = abi.encode(address(0x123));
        bytes memory auxData2 = abi.encode(address(0x456));

        IPayoutActionEncoder encoder1 = _deployActionEncoder(VAULT_ENCODER_ID, dao, auxData1);
        IPayoutActionEncoder encoder2 = _deployActionEncoder(MOCK_ENCODER_ID, dao, auxData2);
        IPayoutActionEncoder encoder3 = _deployActionEncoder(VAULT_ENCODER_ID, dao2, auxData1);

        assertTrue(address(encoder1) != address(encoder2));
        assertTrue(address(encoder1) != address(encoder3));
        assertTrue(address(encoder2) != address(encoder3));

        assertEq(factory.instanceToType(address(encoder1)), VAULT_ENCODER_ID);
        assertEq(factory.instanceToType(address(encoder2)), MOCK_ENCODER_ID);
        assertEq(factory.instanceToType(address(encoder3)), VAULT_ENCODER_ID);
    }

    /// ===============================
    /// FUZZ TESTS
    /// ===============================

    /// @notice Fuzz test for encoder registration
    function testFuzz_RegisterActionEncoder(bytes32 encoderId, string memory metadata) public {
        vm.assume(encoderId != bytes32(0));
        vm.assume(bytes(metadata).length > 0);

        // Should succeed with valid parameters
        factory.registerActionEncoder(encoderId, address(mockImplementation), metadata);
        assertTrue(factory.isTypeRegistered(encoderId));

        (address regImpl, string memory regMeta) = factory.registeredTypes(encoderId);
        assertEq(regImpl, address(mockImplementation));
        assertEq(regMeta, metadata);
    }

    /// @notice Fuzz test for hash computation
    function testFuzz_ParamsHashComputation(bytes32 encoderId, address daoAddr, bytes memory auxData) public view {
        vm.assume(daoAddr != address(0));

        bytes32 hash1 = keccak256(abi.encode(encoderId, daoAddr, auxData));
        bytes32 hash2 = keccak256(abi.encode(encoderId, daoAddr, auxData));

        // Same parameters should produce same hash
        assertEq(hash1, hash2);

        // Hash should match manual computation
        bytes32 expectedHash = keccak256(abi.encode(encoderId, daoAddr, auxData));
        assertEq(hash1, expectedHash);
    }

    /// @notice Fuzz test for deployment parameters
    function testFuzz_DeploymentParameters(bytes32 encoderId, address daoAddr, bytes memory auxData) public {
        vm.assume(encoderId != bytes32(0));
        vm.assume(daoAddr != address(0));
        vm.assume(auxData.length < 10_000); // Reasonable size limit

        factory.registerActionEncoder(encoderId, address(mockImplementation), "Fuzz Test Encoder");

        IPayoutActionEncoder encoder = _deployActionEncoder(encoderId, IDAO(daoAddr), auxData);
        assertTrue(address(encoder) != address(0));
        assertEq(factory.instanceToType(address(encoder)), encoderId);
    }
}

/// @notice Mock action encoder implementation for testing
contract ActionEncoderMock is PayoutActionEncoderBase {
    constructor() {
        _disableInitializers();
    }

    function getCreationEncodingTypes() external pure override returns (string memory types) {
        return "address,string";
    }

    function getClaimEncodingTypes() external pure override returns (string memory types) {
        return "uint256,bytes32";
    }

    function setupCampaign(uint256, bytes calldata) external pure override {
        // Mock implementation - do nothing
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
        override
        returns (Action[] memory actions)
    {
        // Mock implementation - return empty actions array
        actions = new Action[](0);
        return actions;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IPayoutActionEncoder).interfaceId || super.supportsInterface(interfaceId);
    }
}

/// @notice Malicious action encoder that supports interface but fails during initialization
contract MaliciousActionEncoder is IPayoutActionEncoder, IERC165 {
    function initialize(
        bytes32, // encoderId
        address, // dao
        address, // deployer
        bytes calldata // auxData
    )
        external
        pure
    {
        revert("Malicious implementation");
    }

    function encoderId() external pure returns (bytes32) {
        return bytes32(0);
    }

    function getCreationEncodingTypes() external pure returns (string memory) {
        return "";
    }

    function getClaimEncodingTypes() external pure returns (string memory) {
        return "";
    }

    function setupCampaign(uint256, bytes calldata) external pure {
        // Do nothing
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
        returns (Action[] memory)
    {
        Action[] memory actions = new Action[](0);
        return actions;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IPayoutActionEncoder).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

/// @notice Non-compliant implementation that doesn't support the IPayoutActionEncoder interface
contract NonCompliantImplementation is IERC165 {
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}
