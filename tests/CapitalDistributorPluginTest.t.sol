// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29 <0.9.0;

import {Test} from "forge-std/src/Test.sol";
import {console2} from "forge-std/src/console2.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {CapitalDistributorPlugin} from "../src/CapitalDistributorPlugin.sol";

contract CapitalDistributorPluginTest is Test {
    address admin = address(0xb0b);
    address user1 = address(0xa1);
    address user2 = address(0xa2);

    DAO internal dao;
    CapitalDistributorPlugin internal capitalDistributorPlugin;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        // Instantiate the contract-under-test.
        // dao = createTestDAO(admin);
    }
}
