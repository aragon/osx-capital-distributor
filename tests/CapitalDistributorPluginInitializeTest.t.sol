// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IDAO } from "@aragon/commons/dao/IDAO.sol";
import { CapitalDistributorPlugin } from "../src/CapitalDistributorPlugin.sol";
import { AllocatorStrategyFactory } from "../src/factories/AllocatorStrategyFactory.sol";
import { ActionEncoderFactory } from "../src/factories/ActionEncoderFactory.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Minimal mock DAO contract for testing
contract MockDAO {
// Minimal implementation - just needs to be a contract
}

contract CapitalDistributorPluginInitializeTest is Test {
    IDAO dao;
    AllocatorStrategyFactory allocatorStrategyFactory;
    ActionEncoderFactory actionEncoderFactory;

    address constant EOA_ADDRESS = address(0x1234);

    function setUp() public {
        // Create mock DAO by deploying a minimal contract
        address mockDao = address(new MockDAO());
        dao = IDAO(mockDao);

        // Deploy factories
        allocatorStrategyFactory = new AllocatorStrategyFactory();
        actionEncoderFactory = new ActionEncoderFactory();
    }

    function deployPluginWithProxy(
        IDAO _dao,
        AllocatorStrategyFactory _allocatorFactory,
        ActionEncoderFactory _actionFactory
    )
        internal
        returns (CapitalDistributorPlugin)
    {
        // Deploy implementation
        CapitalDistributorPlugin implementation = new CapitalDistributorPlugin();

        // Deploy proxy and initialize
        bytes memory initData =
            abi.encodeCall(CapitalDistributorPlugin.initialize, (_dao, _allocatorFactory, _actionFactory));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return CapitalDistributorPlugin(address(proxy));
    }

    function test_InitializeWithValidParameters() public {
        CapitalDistributorPlugin plugin = deployPluginWithProxy(dao, allocatorStrategyFactory, actionEncoderFactory);

        // Verify state was set correctly
        assertEq(address(plugin.dao()), address(dao));
        assertEq(address(plugin.allocatorStrategyFactory()), address(allocatorStrategyFactory));
        assertEq(address(plugin.actionEncoderFactory()), address(actionEncoderFactory));
    }

    function test_InitializeWithValidParametersAndZeroActionEncoder() public {
        CapitalDistributorPlugin plugin =
            deployPluginWithProxy(dao, allocatorStrategyFactory, ActionEncoderFactory(address(0)));

        // Verify state was set correctly
        assertEq(address(plugin.dao()), address(dao));
        assertEq(address(plugin.allocatorStrategyFactory()), address(allocatorStrategyFactory));
        assertEq(address(plugin.actionEncoderFactory()), address(0));
    }

    function test_RevertWhen_InitializeWithZeroDAO() public {
        // Deploy implementation
        CapitalDistributorPlugin implementation = new CapitalDistributorPlugin();

        // Should revert when DAO is zero address
        bytes memory initData = abi.encodeCall(
            CapitalDistributorPlugin.initialize, (IDAO(address(0)), allocatorStrategyFactory, actionEncoderFactory)
        );

        vm.expectRevert(abi.encodeWithSelector(CapitalDistributorPlugin.ZeroAddress.selector, "_dao"));
        new ERC1967Proxy(address(implementation), initData);
    }

    function test_RevertWhen_InitializeWithZeroAllocatorStrategyFactory() public {
        // Deploy implementation
        CapitalDistributorPlugin implementation = new CapitalDistributorPlugin();

        // Should revert when allocatorStrategyFactory is zero address
        bytes memory initData = abi.encodeCall(
            CapitalDistributorPlugin.initialize, (dao, AllocatorStrategyFactory(address(0)), actionEncoderFactory)
        );

        vm.expectRevert(
            abi.encodeWithSelector(CapitalDistributorPlugin.InvalidParameter.selector, "_allocatorStrategyFactory")
        );
        new ERC1967Proxy(address(implementation), initData);
    }

    function test_RevertWhen_InitializeWithEOAAllocatorStrategyFactory() public {
        // Deploy implementation
        CapitalDistributorPlugin implementation = new CapitalDistributorPlugin();

        // Should revert when allocatorStrategyFactory is EOA (not a contract)
        bytes memory initData = abi.encodeCall(
            CapitalDistributorPlugin.initialize, (dao, AllocatorStrategyFactory(EOA_ADDRESS), actionEncoderFactory)
        );

        vm.expectRevert(
            abi.encodeWithSelector(CapitalDistributorPlugin.InvalidParameter.selector, "_allocatorStrategyFactory")
        );
        new ERC1967Proxy(address(implementation), initData);
    }

    function test_RevertWhen_InitializeWithEOAActionEncoderFactory() public {
        // Deploy implementation
        CapitalDistributorPlugin implementation = new CapitalDistributorPlugin();

        // Should revert when actionEncoderFactory is EOA (not a contract)
        bytes memory initData = abi.encodeCall(
            CapitalDistributorPlugin.initialize, (dao, allocatorStrategyFactory, ActionEncoderFactory(EOA_ADDRESS))
        );

        vm.expectRevert(
            abi.encodeWithSelector(CapitalDistributorPlugin.InvalidParameter.selector, "_actionEncoderFactory")
        );
        new ERC1967Proxy(address(implementation), initData);
    }

    function test_InitializeCanOnlyBeCalledOnce() public {
        CapitalDistributorPlugin plugin = deployPluginWithProxy(dao, allocatorStrategyFactory, actionEncoderFactory);

        // Second initialization should fail
        vm.expectRevert("Initializable: contract is already initialized");
        plugin.initialize(dao, allocatorStrategyFactory, actionEncoderFactory);
    }

    function testFuzz_InitializeWithRandomValidAddresses(
        address _dao,
        address _allocatorFactory,
        address _actionFactory
    )
        public
    {
        // Skip invalid inputs
        vm.assume(_dao != address(0));
        vm.assume(_allocatorFactory != address(0));

        // Skip precompile addresses (0x1 to 0x9)
        vm.assume(uint160(_dao) > 9);
        vm.assume(uint160(_allocatorFactory) > 9);
        vm.assume(_actionFactory == address(0) || uint160(_actionFactory) > 9);

        // Deploy contracts at the addresses to make them valid
        vm.etch(_dao, address(dao).code);
        vm.etch(_allocatorFactory, address(allocatorStrategyFactory).code);
        if (_actionFactory != address(0)) {
            vm.etch(_actionFactory, address(actionEncoderFactory).code);
        }

        // Deploy new plugin with proxy for this test
        CapitalDistributorPlugin plugin = deployPluginWithProxy(
            IDAO(_dao), AllocatorStrategyFactory(_allocatorFactory), ActionEncoderFactory(_actionFactory)
        );

        // Verify state
        assertEq(address(plugin.dao()), _dao);
        assertEq(address(plugin.allocatorStrategyFactory()), _allocatorFactory);
        assertEq(address(plugin.actionEncoderFactory()), _actionFactory);
    }
}
