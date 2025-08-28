# 🧪 FactoryBase.test.md

## 🔧 Contract: ./src/FactoryBase.sol

## 🧠 Function Overview

I want you to write an in-depth test suite for the factory base contract. It's used by two other contracts as the shared
based:

- AllocatorStrategyFactory.sol
- ActionEncoderFactory.sol

These contracts serve as registry and factories for other contracts. These contracts can be of two types: ActionEncoders
and AllocatorStrategies. But for the FactoryBase, that's not of importance. While doing the testing, I want you to think
about:

- Testing the functionality
- Thinking of ways the functionality could fail either logically, programmatically or mathematically.
- Think security ways to make the functionality to fail, break or output something it shouldn't.

## Process

You shouldn't just test it, but raise and write a report at the end with all the findings and logic you would like to
change, refactor or failures you've found for me. Don't change the logic code of the contract until the end and inform
me before hand of all the changes, again through that written report. Then after wards, we plan and I'll inform you how
to proceed.
