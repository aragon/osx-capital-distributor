// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.29 <0.9.0;

import { AragonTest } from "../helpers/AragonTest.sol";
import { DirectAllocationStrategy } from "../../src/allocatorStrategies/DirectAllocationStrategy.sol";
import { IAllocatorStrategy } from "../../src/interfaces/IAllocatorStrategy.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { SetDirectAllocationsFromCsv } from "../../script/utils/SetDirectAllocationsFromCsv.s.sol";

contract DirectAllocationStrategyTest is AragonTest {
    DirectAllocationStrategy implementation;
    DirectAllocationStrategy strategy;
    address manager;

    function setUp() public {
        implementation = new DirectAllocationStrategy();
        address clone = Clones.clone(address(implementation));
        strategy = DirectAllocationStrategy(clone);
        manager = pluginAddress[0];

        vm.prank(manager);
        strategy.initialize(toBytes32("direct-allocation"), createdDao, manager, "");
    }

    function test_SetAllocationCampaignInitializesOnce() public {
        vm.prank(manager);
        strategy.setAllocationCampaign(1, "");

        bool initialized = strategy.directCampaigns(1);
        assertTrue(initialized, "Campaign should be initialized");

        vm.expectRevert(abi.encodeWithSelector(DirectAllocationStrategy.CampaignAlreadyInitialized.selector, 1));
        vm.prank(manager);
        strategy.setAllocationCampaign(1, "");
    }

    function test_SetAllocationCampaignRequiresOwnerOrDao() public {
        vm.expectRevert(abi.encodeWithSelector(IAllocatorStrategy.NotAuthorized.selector, randomWallet));
        vm.prank(randomWallet);
        strategy.setAllocationCampaign(1, "");
    }

    function test_SetAllocationCampaignRejectsAuxData() public {
        vm.expectRevert(DirectAllocationStrategy.InvalidAllocationInput.selector);
        vm.prank(manager);
        strategy.setAllocationCampaign(1, bytes("bad"));
    }

    function test_SetAllocationsStoresValues() public {
        vm.prank(manager);
        strategy.setAllocationCampaign(7, "");

        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        vm.prank(manager);
        strategy.setAllocations(7, recipients, amounts);

        assertEq(strategy.getAllocation(7, alice), 1 ether, "Alice allocation mismatch");
        assertEq(strategy.getAllocation(7, bob), 2 ether, "Bob allocation mismatch");
        assertEq(strategy.getTotalClaimableAmount(7, alice, ""), 1 ether, "Claimable amount mismatch");
    }

    function test_SetAllocationsRejectsBeforeInitialization() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.expectRevert(abi.encodeWithSelector(DirectAllocationStrategy.CampaignNotInitialized.selector, 1));
        vm.prank(manager);
        strategy.setAllocations(1, recipients, amounts);
    }

    function test_SetAllocationsRejectsInvalidArrayLengths() public {
        vm.prank(manager);
        strategy.setAllocationCampaign(2, "");

        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.expectRevert(DirectAllocationStrategy.InvalidAllocationInput.selector);
        vm.prank(manager);
        strategy.setAllocations(2, recipients, amounts);
    }

    function test_SetAllocationsRejectsZeroRecipientOrAmount() public {
        vm.prank(manager);
        strategy.setAllocationCampaign(3, "");

        address[] memory badRecipients = new address[](1);
        badRecipients[0] = address(0);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.expectRevert(DirectAllocationStrategy.InvalidAllocationInput.selector);
        vm.prank(manager);
        strategy.setAllocations(3, badRecipients, amounts);

        badRecipients[0] = alice;
        amounts[0] = 0;

        vm.expectRevert(DirectAllocationStrategy.InvalidAllocationInput.selector);
        vm.prank(manager);
        strategy.setAllocations(3, badRecipients, amounts);
    }

    function test_SetAllocationsRejectsDuplicates() public {
        vm.prank(manager);
        strategy.setAllocationCampaign(4, "");

        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.prank(manager);
        strategy.setAllocations(4, recipients, amounts);

        vm.expectRevert(abi.encodeWithSelector(DirectAllocationStrategy.AllocationAlreadySet.selector, 4, alice));
        vm.prank(manager);
        strategy.setAllocations(4, recipients, amounts);
    }

    function test_SetAllocationHelperStoresValue() public {
        vm.prank(manager);
        strategy.setAllocationCampaign(5, "");

        vm.prank(manager);
        strategy.setAllocation(5, alice, 5 ether);

        assertEq(strategy.getAllocation(5, alice), 5 ether, "Single allocation mismatch");
    }

    function test_GetTotalClaimableAmountReturnsZeroForAuxData() public {
        vm.prank(manager);
        strategy.setAllocationCampaign(6, "");

        vm.prank(manager);
        strategy.setAllocation(6, alice, 3 ether);

        assertEq(strategy.getTotalClaimableAmount(6, alice, ""), 3 ether, "Expected allocation");
        assertEq(
            strategy.getTotalClaimableAmount(6, alice, abi.encodePacked(uint256(1))),
            0,
            "Aux data should zero out claim"
        );
    }

    function test_SetAllocationRequiresOwnerOrDao() public {
        vm.prank(manager);
        strategy.setAllocationCampaign(8, "");

        vm.expectRevert(abi.encodeWithSelector(IAllocatorStrategy.NotAuthorized.selector, randomWallet));
        vm.prank(randomWallet);
        strategy.setAllocation(8, alice, 1 ether);
    }

    function test_ScriptExecuteBatchesAllocations() public {
        vm.prank(manager);
        strategy.setAllocationCampaign(9, "");

        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = carol;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;

        SetDirectAllocationsFromCsv allocationScript = new SetDirectAllocationsFromCsv();

        vm.prank(manager);
        allocationScript.execute(address(strategy), 9, recipients, amounts, 2);

        assertEq(strategy.getAllocation(9, alice), 1 ether, "Alice allocation mismatch");
        assertEq(strategy.getAllocation(9, bob), 2 ether, "Bob allocation mismatch");
        assertEq(strategy.getAllocation(9, carol), 3 ether, "Carol allocation mismatch");
    }

    function test_ScriptExecuteRevertsOnMismatchedArrays() public {
        vm.prank(manager);
        strategy.setAllocationCampaign(10, "");

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        SetDirectAllocationsFromCsv allocationScript = new SetDirectAllocationsFromCsv();

        vm.expectRevert(SetDirectAllocationsFromCsv.MismatchedAllocationArrays.selector);
        vm.prank(manager);
        allocationScript.execute(address(strategy), 10, recipients, amounts, 0);
    }

}
