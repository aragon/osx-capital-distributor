# 🧪 AllocatorStrategyFactory.test.md

## 🔧 Contract: ./src/AllocatorStrategyFactory.sol

## 🧠 Function Overview
I want you to write an in-depth test suite for the AllocatorStrategyFactory. Assume the FactoryBase is already tested, so you don't have to do that already.

You can use mocks for some of the contracts in the registry, but there's also some inside the allocatorStrategies/ directory. The most important one is the MerkleDistributor.

This contract serves as a registry and factory for allocator strategies, that is, contracts that following an interface (you can find it in the interfaces directory) allocate some funds to an address. Each implementation may have its own logic to decide how to do that.

While doing the testing, I want you to think about:
- Testing the functionality
- Thinking of ways the functionality could fail either logically, programmatically or mathematically.
- Think security ways to make the functionality to fail, break or output something it shouldn't.

## Process
You shouldn't just test it, but raise and write a report at the end with all the findings and logic you would like to change, refactor or failures you've found for me.
Don't change the logic code of the contract until the end and inform me before hand of all the changes, again through that written report.
Then after wards, we plan and I'll inform you how to proceed.
