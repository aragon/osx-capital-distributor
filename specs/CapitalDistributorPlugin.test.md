# 🧪 CapitalDistributorPlugin.test.md

## 🔧 Contract: ./src/CapitalDistributorPlugin

## 🧠 Function Overview

The function of this plugin is to be core of the rest of the Capital Distributor functionality for Aragon OSx. The DAO
should be able to create campaigns to distribute funds from it based on different allocation strategies and then
distributing it based on actions encoding (the calldata to execute the payout).

You may start the test with something like this:

```

```

pragma solidity >=0.8.29 <0.9.0;

import {Test} from "forge-std/Test.sol"; import {console2} from "forge-std/console2.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {IPayoutActionEncoder} from "../src/interfaces/IPayoutActionEncoder.sol"; import {CapitalDistributorPlugin} from
"../src/CapitalDistributorPlugin.sol"; import {AragonTest} from "./helpers/AragonTest.sol"; import {IAllocatorStrategy}
from "../src/interfaces/IAllocatorStrategy.sol"; import {AllocatorStrategyMock} from
"./mocks/AllocatorStrategyMock.sol"; import {VaultDepositPayoutActionEncoder} from
"../src/payoutActionEncoders/VaultDepositPayoutActionEncoder.sol"; import {IAllocatorStrategyFactory} from
"../src/interfaces/IAllocatorStrategyFactory.sol";

import {MintableERC20} from "./mocks/MintableERC20.sol"; import {ERC4626Mock} from "./mocks/ERC4626Mock.sol"; import
{IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract CapitalDistributorPluginTest is AragonTest { CapitalDistributorPlugin capitalDistributorPlugin;
AllocatorStrategyMock strategy; MintableERC20 token; ERC4626Mock vaultToSendTokens; VaultDepositPayoutActionEncoder
vaultDepositActionEncoder;

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

```

```

---

## 🧪 Test Details

### T01: Create a Campaign

Description: The test should call the deployed capital distributor plugin and create a campaign with the most basic
parameters:

- Empty metadata
- "mock-strategy" as the allocation strategy
- empty bytes for the encoder
- a basic erc20 token
- empty bytes32 for the action encoder id
- empty bytes for the aux data for the action encoder
- false so users can only claim once
- 0 // for when the campaign starts
- 0 // for when expires the campaign

Success: the tests should query the values and make sure they are right Success: the tests should ensure the event
emitted is the correct one

Once that first test is done and passing, you may write the following variations to make sure the edge cases are working

- Check campaign creation with different type of values and ensure they make sense
- Make a test for the campaign start variable
- Make a test for the campaign ending variable
- Make a test that pranks a random address and try to create a campaign and failing
- For the action encoder and allocation strategy you may just expect that returns an address, no need to verify yet its'
  the correct one. That's for the factory to verify.

### T02: Payout is claimed

Description: Now that we've tested the campaign creation, I want to make sure the logic that pertains to the claiming on
the CapitalDistributorPlugin is fully tested. You may find a reference implementation of this on the
CapitalDistributorPluginTest contract under tests with the name 'test_PayoutIsSent'.

After the first basic test is done, then implement the same but with different types of campaigns created. For example:

- Multiple claims allowed
- Try claiming before the start date (and expect it to fail)
- Try claiming after the end date (and expect it to fail)
- Try claiming after already claiming (and expect it to fail)
