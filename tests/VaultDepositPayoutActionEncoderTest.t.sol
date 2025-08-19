// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {VaultDepositPayoutActionEncoder, IVault} from "../src/payoutActionEncoders/VaultDepositPayoutActionEncoder.sol";
import {ActionEncoderFactory} from "../src/factories/ActionEncoderFactory.sol";
import {IPayoutActionEncoder} from "../src/interfaces/IPayoutActionEncoder.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IDAO} from "@aragon/commons/dao/IDAO.sol";
import {Action} from "@aragon/commons/executors/IExecutor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {AragonTest} from "./helpers/AragonTest.sol";

/// @title VaultDepositPayoutActionEncoderTest
/// @notice Comprehensive test suite for VaultDepositPayoutActionEncoder
/// @dev Tests all functionality including initialization, vault setup, action building, and edge cases
contract VaultDepositPayoutActionEncoderTest is AragonTest {
    VaultDepositPayoutActionEncoder public encoder;
    ActionEncoderFactory public factory;
    
    bytes32 constant VAULT_ENCODER_ID = keccak256("vault-deposit-encoder");
    string constant VAULT_METADATA = "Vault Deposit Encoder";
    
    address testAlice = makeAddr("testAlice");
    address testBob = makeAddr("testBob");
    
    MockVault public mockVault;
    MockToken public mockToken;
    
    uint256 constant CAMPAIGN_ID = 1;
    uint256 constant DEFAULT_AMOUNT = 1000 ether;
    
    event CampaignVaultSet(uint256 indexed campaignId, address indexed vaultAddress, address indexed setter);
    
    function setUp() public {
        
        // Deploy factory
        factory = new ActionEncoderFactory();
        
        // Deploy mock contracts
        mockVault = new MockVault();
        mockToken = new MockToken();
        
        // Register encoder implementation
        VaultDepositPayoutActionEncoder implementation = new VaultDepositPayoutActionEncoder();
        factory.registerActionEncoder(VAULT_ENCODER_ID, address(implementation), VAULT_METADATA);
        
        // Deploy encoder instance
        bytes memory auxData = abi.encode(address(mockVault));
        encoder = VaultDepositPayoutActionEncoder(
            address(factory.deployActionEncoder(VAULT_ENCODER_ID, createdDAO, auxData))
        );
    }
    
    // ============================================
    // Initialization & Setup Tests
    // ============================================
    
    function test_Initialization_Success() public {
        // Deploy a fresh encoder with different parameters
        address newVault = makeAddr("newTestVault");
        bytes memory auxData = abi.encode(newVault);
        
        // Create a new DAO for this test
        DAO testDAO = DAO(payable(address(new MockDAO())));
        
        address newEncoder = address(factory.deployActionEncoder(VAULT_ENCODER_ID, IDAO(address(testDAO)), auxData));
        
        VaultDepositPayoutActionEncoder deployedEncoder = VaultDepositPayoutActionEncoder(newEncoder);
        
        // Verify initialization
        assertEq(address(deployedEncoder.dao()), address(testDAO));
        assertEq(deployedEncoder.encoderId(), VAULT_ENCODER_ID);
        assertEq(deployedEncoder.owner(), address(this));
    }
    
    function test_SetupCampaign_Success() public {
        address newVault = makeAddr("newVault");
        
        vm.expectEmit(true, true, true, true);
        emit CampaignVaultSet(CAMPAIGN_ID, newVault, address(createdDAO));
        
        vm.prank(address(createdDAO));
        encoder.setupCampaign(CAMPAIGN_ID, abi.encode(newVault));
        
        assertEq(encoder.campaignVaults(CAMPAIGN_ID), newVault);
    }
    
    function test_SetupCampaign_RevertNotDAO() public {
        address newVault = makeAddr("newVault");
        
        vm.prank(testAlice);
        vm.expectRevert(abi.encodeWithSelector(VaultDepositPayoutActionEncoder.OnlyDAO.selector, testAlice));
        encoder.setupCampaign(CAMPAIGN_ID, abi.encode(newVault));
    }
    
    function test_SetupCampaign_RevertZeroVault() public {
        vm.prank(address(createdDAO));
        vm.expectRevert(VaultDepositPayoutActionEncoder.ZeroAddressNotAllowed.selector);
        encoder.setupCampaign(CAMPAIGN_ID, abi.encode(address(0)));
    }
    
    function test_SetupCampaign_OwnerCanSetup() public {
        address newVault = makeAddr("newVault");
        address owner = encoder.owner();
        
        vm.expectEmit(true, true, true, true);
        emit CampaignVaultSet(CAMPAIGN_ID, newVault, owner);
        
        vm.prank(owner);
        encoder.setupCampaign(CAMPAIGN_ID, abi.encode(newVault));
        
        assertEq(encoder.campaignVaults(CAMPAIGN_ID), newVault);
    }
    
    // ============================================
    // Action Building Tests
    // ============================================
    
    function test_BuildActions_Success() public {
        // Setup vault for campaign
        vm.prank(address(createdDAO));
        encoder.setupCampaign(CAMPAIGN_ID, abi.encode(address(mockVault)));
        
        // Build actions
        Action[] memory actions = encoder.buildActions(
            mockToken,
            testAlice,
            DEFAULT_AMOUNT,
            address(this), // caller (not used)
            CAMPAIGN_ID,
            bytes("") // auxData (not used)
        );
        
        // Verify action array
        assertEq(actions.length, 2);
        assertEq(actions[0].to, address(mockToken));
        assertEq(actions[0].value, 0);
        assertEq(actions[1].to, address(mockVault));
        assertEq(actions[1].value, 0);
    }
    
    function test_BuildActions_CorrectApprovalAction() public {
        // Setup vault
        vm.prank(address(createdDAO));
        encoder.setupCampaign(CAMPAIGN_ID, abi.encode(address(mockVault)));
        
        // Build actions
        Action[] memory actions = encoder.buildActions(
            mockToken,
            testAlice,
            DEFAULT_AMOUNT,
            address(this),
            CAMPAIGN_ID,
            bytes("")
        );
        
        // Verify approval action
        assertEq(actions[0].to, address(mockToken));
        assertEq(actions[0].value, 0);
        
        // Decode the action data
        bytes4 selector = bytes4(actions[0].data);
        assertEq(selector, IERC20.approve.selector);
        
        // Extract parameters (skip selector)
        (address spender, uint256 approveAmount) = abi.decode(
            slice(actions[0].data, 4, actions[0].data.length - 4),
            (address, uint256)
        );
        
        assertEq(spender, address(mockVault));
        assertEq(approveAmount, DEFAULT_AMOUNT);
    }
    
    function test_BuildActions_CorrectDepositAction() public {
        // Setup vault
        vm.prank(address(createdDAO));
        encoder.setupCampaign(CAMPAIGN_ID, abi.encode(address(mockVault)));
        
        // Build actions
        Action[] memory actions = encoder.buildActions(
            mockToken,
            testAlice,
            DEFAULT_AMOUNT,
            address(this),
            CAMPAIGN_ID,
            bytes("")
        );
        
        // Verify deposit action
        assertEq(actions[1].to, address(mockVault));
        assertEq(actions[1].value, 0);
        
        // Decode the action data
        bytes4 selector = bytes4(actions[1].data);
        assertEq(selector, IVault.deposit.selector);
        
        // Extract parameters
        (uint256 depositAmount, address depositRecipient) = abi.decode(
            slice(actions[1].data, 4, actions[1].data.length - 4),
            (uint256, address)
        );
        
        assertEq(depositAmount, DEFAULT_AMOUNT);
        assertEq(depositRecipient, testAlice);
    }
    
    function test_BuildActions_RevertZeroAmount() public {
        // Setup vault
        vm.prank(address(createdDAO));
        encoder.setupCampaign(CAMPAIGN_ID, abi.encode(address(mockVault)));
        
        // Try to build actions with zero amount
        vm.expectRevert(VaultDepositPayoutActionEncoder.AmountCannotBeZero.selector);
        encoder.buildActions(
            mockToken,
            testAlice,
            0, // zero amount
            address(this),
            CAMPAIGN_ID,
            bytes("")
        );
    }
    
    function test_BuildActions_RevertNoVault() public {
        // Don't setup vault, try to build actions
        vm.expectRevert(
            abi.encodeWithSelector(VaultDepositPayoutActionEncoder.VaultNotSetForCampaign.selector, CAMPAIGN_ID)
        );
        encoder.buildActions(
            mockToken,
            testAlice,
            DEFAULT_AMOUNT,
            address(this),
            CAMPAIGN_ID,
            bytes("")
        );
    }
    
    function test_BuildActions_DifferentCampaigns() public {
        address vault1 = makeAddr("vault1");
        address vault2 = makeAddr("vault2");
        uint256 campaign2 = 2;
        
        // Setup different vaults for different campaigns
        vm.startPrank(address(createdDAO));
        encoder.setupCampaign(CAMPAIGN_ID, abi.encode(vault1));
        encoder.setupCampaign(campaign2, abi.encode(vault2));
        vm.stopPrank();
        
        // Build actions for campaign 1
        Action[] memory actions1 = encoder.buildActions(
            mockToken,
            testAlice,
            DEFAULT_AMOUNT,
            address(this),
            CAMPAIGN_ID,
            bytes("")
        );
        
        // Build actions for campaign 2
        Action[] memory actions2 = encoder.buildActions(
            mockToken,
            testBob,
            DEFAULT_AMOUNT * 2,
            address(this),
            campaign2,
            bytes("")
        );
        
        // Verify different vaults used
        assertEq(actions1[1].to, vault1);
        assertEq(actions2[1].to, vault2);
    }
    
    function test_BuildActions_SameVaultMultipleCampaigns() public {
        uint256 campaign2 = 2;
        uint256 campaign3 = 3;
        
        // Setup same vault for multiple campaigns
        vm.startPrank(address(createdDAO));
        encoder.setupCampaign(CAMPAIGN_ID, abi.encode(address(mockVault)));
        encoder.setupCampaign(campaign2, abi.encode(address(mockVault)));
        encoder.setupCampaign(campaign3, abi.encode(address(mockVault)));
        vm.stopPrank();
        
        // Build actions for all campaigns
        Action[] memory actions1 = encoder.buildActions(mockToken, testAlice, 100 ether, address(this), CAMPAIGN_ID, "");
        Action[] memory actions2 = encoder.buildActions(mockToken, testBob, 200 ether, address(this), campaign2, "");
        Action[] memory actions3 = encoder.buildActions(mockToken, testAlice, 300 ether, address(this), campaign3, "");
        
        // All should use same vault
        assertEq(actions1[1].to, address(mockVault));
        assertEq(actions2[1].to, address(mockVault));
        assertEq(actions3[1].to, address(mockVault));
    }
    
    function testFuzz_BuildActions_Amounts(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 2); // Avoid overflow in tests
        
        // Setup vault
        vm.prank(address(createdDAO));
        encoder.setupCampaign(CAMPAIGN_ID, abi.encode(address(mockVault)));
        
        // Build actions with fuzzed amount
        Action[] memory actions = encoder.buildActions(
            mockToken,
            testAlice,
            amount,
            address(this),
            CAMPAIGN_ID,
            bytes("")
        );
        
        // Verify approval amount
        (, uint256 approveAmount) = abi.decode(
            slice(actions[0].data, 4, actions[0].data.length - 4),
            (address, uint256)
        );
        assertEq(approveAmount, amount);
        
        // Verify deposit amount
        (uint256 depositAmount,) = abi.decode(
            slice(actions[1].data, 4, actions[1].data.length - 4),
            (uint256, address)
        );
        assertEq(depositAmount, amount);
    }
    
    // ============================================
    // Encoding Tests
    // ============================================
    
    function test_GetCreationEncodingTypes() public {
        assertEq(encoder.getCreationEncodingTypes(), "address");
    }
    
    function test_GetClaimEncodingTypes() public {
        assertEq(encoder.getClaimEncodingTypes(), "");
    }
    
    function test_CreationAuxDataDecoding() public {
        address testVault = makeAddr("testVault");
        bytes memory auxData = abi.encode(testVault);
        
        vm.prank(address(createdDAO));
        encoder.setupCampaign(99, auxData);
        
        assertEq(encoder.campaignVaults(99), testVault);
    }
    
    function test_InvalidAuxDataLength() public {
        // Create invalid auxData (too short)
        bytes memory invalidData = hex"1234";
        
        vm.prank(address(createdDAO));
        vm.expectRevert(); // Abi decoding error
        encoder.setupCampaign(CAMPAIGN_ID, invalidData);
    }
    
    // ============================================
    // Integration Tests
    // ============================================
    
    function test_FactoryIntegration_FullFlow() public {
        // Deploy new encoder via factory
        address newVault = address(new MockVault());
        bytes memory auxData = abi.encode(newVault);
        
        address newEncoderAddr = address(factory.deployActionEncoder(VAULT_ENCODER_ID, createdDAO, auxData));
        VaultDepositPayoutActionEncoder newEncoder = VaultDepositPayoutActionEncoder(newEncoderAddr);
        
        // Setup campaign
        vm.prank(address(createdDAO));
        newEncoder.setupCampaign(10, auxData);
        
        // Build actions
        Action[] memory actions = newEncoder.buildActions(
            mockToken,
            testAlice,
            500 ether,
            address(this),
            10,
            bytes("")
        );
        
        // Verify flow worked
        assertEq(actions.length, 2);
        assertEq(newEncoder.campaignVaults(10), newVault);
    }
    
    function test_Integration_WithMockVault() public {
        // Setup
        vm.prank(address(createdDAO));
        encoder.setupCampaign(CAMPAIGN_ID, abi.encode(address(mockVault)));
        
        // Give DAO tokens
        mockToken.mint(address(createdDAO), DEFAULT_AMOUNT);
        
        // Build actions
        Action[] memory actions = encoder.buildActions(
            mockToken,
            testAlice,
            DEFAULT_AMOUNT,
            address(createdDAO),
            CAMPAIGN_ID,
            bytes("")
        );
        
        // Execute actions as DAO
        vm.startPrank(address(createdDAO));
        
        // Execute approval
        (bool success1,) = actions[0].to.call(actions[0].data);
        assertTrue(success1);
        
        // Verify approval
        assertEq(mockToken.allowance(address(createdDAO), address(mockVault)), DEFAULT_AMOUNT);
        
        // Execute deposit
        (bool success2,) = actions[1].to.call(actions[1].data);
        assertTrue(success2);
        
        // Verify deposit was recorded
        assertEq(mockVault.deposits(testAlice), DEFAULT_AMOUNT);
        
        vm.stopPrank();
    }
    
    function test_Integration_MultipleEncoders() public {
        // Deploy second encoder for different DAO
        DAO secondDAO = DAO(payable(address(new MockDAO())));
        address vault2 = address(new MockVault());
        
        VaultDepositPayoutActionEncoder encoder2 = VaultDepositPayoutActionEncoder(
            address(factory.deployActionEncoder(VAULT_ENCODER_ID, IDAO(address(secondDAO)), abi.encode(vault2)))
        );
        
        // Setup campaigns on both encoders
        vm.prank(address(createdDAO));
        encoder.setupCampaign(1, abi.encode(address(mockVault)));
        
        vm.prank(address(secondDAO));
        encoder2.setupCampaign(1, abi.encode(vault2));
        
        // Build actions from both
        Action[] memory actions1 = encoder.buildActions(mockToken, testAlice, 100 ether, address(this), 1, "");
        Action[] memory actions2 = encoder2.buildActions(mockToken, testBob, 200 ether, address(this), 1, "");
        
        // Verify isolation
        assertEq(actions1[1].to, address(mockVault));
        assertEq(actions2[1].to, vault2);
        assertNotEq(encoder.campaignVaults(1), encoder2.campaignVaults(1));
    }
    
    // ============================================
    // Edge Cases & Security Tests
    // ============================================
    
    function test_LargeAmounts() public {
        uint256 maxAmount = type(uint256).max;
        
        vm.prank(address(createdDAO));
        encoder.setupCampaign(CAMPAIGN_ID, abi.encode(address(mockVault)));
        
        // Should not revert with max uint256
        Action[] memory actions = encoder.buildActions(
            mockToken,
            testAlice,
            maxAmount,
            address(this),
            CAMPAIGN_ID,
            bytes("")
        );
        
        // Verify amounts
        (, uint256 approveAmount) = abi.decode(
            slice(actions[0].data, 4, actions[0].data.length - 4),
            (address, uint256)
        );
        assertEq(approveAmount, maxAmount);
    }
    
    function test_GasOptimization() public {
        vm.prank(address(createdDAO));
        encoder.setupCampaign(CAMPAIGN_ID, abi.encode(address(mockVault)));
        
        uint256 gasBefore = gasleft();
        encoder.buildActions(
            mockToken,
            testAlice,
            DEFAULT_AMOUNT,
            address(this),
            CAMPAIGN_ID,
            bytes("")
        );
        uint256 gasUsed = gasBefore - gasleft();
        
        // Should use less than 100k gas
        assertLt(gasUsed, 100000);
    }
    
    // ============================================
    // Helper Functions
    // ============================================
    
    function slice(bytes memory data, uint256 start, uint256 length) internal pure returns (bytes memory) {
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[i + start];
        }
        return result;
    }
}

// ============================================
// Mock Contracts
// ============================================

contract MockVault is IVault {
    mapping(address => uint256) public deposits;
    
    event DepositMade(uint256 amount, address recipient);
    
    function deposit(uint256 _amount, address _recipient) external override {
        deposits[_recipient] += _amount;
        emit DepositMade(_amount, _recipient);
    }
}

contract MockToken is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    uint256 public totalSupply;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract MockDAO is IDAO {
    mapping(address => mapping(address => mapping(bytes32 => bool))) public permissions;
    
    function hasPermission(
        address _where,
        address _who,
        bytes32 _permissionId,
        bytes memory
    ) external view returns (bool) {
        return permissions[_where][_who][_permissionId];
    }
    
    function grant(address _where, address _who, bytes32 _permissionId) external {
        permissions[_where][_who][_permissionId] = true;
    }
    
    function revoke(address _where, address _who, bytes32 _permissionId) external {
        permissions[_where][_who][_permissionId] = false;
    }
    
    function execute(
        bytes32,
        Action[] calldata,
        uint256
    ) external payable returns (bytes[] memory execResults, uint256 failureMap) {
        // Mock implementation
        return (new bytes[](0), 0);
    }
    
    function deposit(
        address,
        uint256,
        string calldata
    ) external payable {}
    
    function setTrustedForwarder(address) external {}
    
    function getTrustedForwarder() external view returns (address) {
        return address(0);
    }
    
    function setSignatureValidator(address) external {}
    
    function isValidSignature(bytes32, bytes memory) external pure returns (bytes4) {
        return 0x1626ba7e;
    }
    
    function registerStandardCallback(
        bytes4,
        bytes4,
        bytes4
    ) external {}
    
    function setMetadata(bytes calldata) external {}
}