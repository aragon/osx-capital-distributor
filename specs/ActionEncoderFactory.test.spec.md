# 🧪 ActionEncoderFactory.test.spec.md

## 🔧 Contract: ./src/ActionEncoderFactory.sol

## 🧠 Function Overview

I want you to write an in-depth test suite for the ActionEncoderFactory. Assume the FactoryBase is already tested, so
you don't have to do that already.

You can use mocks for some of the contracts in the registry, but there's also some inside the payoutActionEncoders/
directory.

This contract serves as a registry and factory for action encoder strategies, that is, contracts that following an
interface (you can find it in the interfaces directory) tell the plugin how to transfer those assets. This is needed
because sometimes to transfer you call the transfer function of the token, but sometimes is eth, and other times you
have to transfer and delegate, or deposit instead of transfer. There are many possibilities on how to allow for this
from the DAO. This part is really critical, because it's going to have execution over the DAO, so if something goes
wrong, the whole dao is in danger. Please make sure to review thoroughly and do a full security check on what could be
improved.

While doing the testing, I want you to think about:

- Testing the functionality
- Thinking of ways the functionality could fail either logically, programmatically or mathematically.
- Think security ways to make the functionality to fail, break or output something it shouldn't.

## Process

You shouldn't just test it, but raise and write a report at the end with all the findings and logic you would like to
change, refactor or failures you've found for me. Don't change the logic code of the contract until the end and inform
me before hand of all the changes, again through that written report. Then after wards, we plan and I'll inform you how
to proceed.
