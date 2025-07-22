# 🧪 MerkleDistributorStrategy.spec.md

## 🔧 Contract: ./src/allocatorStrategies/MerkleDistributorStrategy.sol

## 🧠 Function Overview
This contract is an allocator strategy, that is, based on a campaign created by the CapitalDistributorPlugin, it assigns an amount to each of the claims. It does that based on a merkle tree that is created offchain and uploaded the root onchain.
It's going to be used mainly for airdrops and reward distributions for things that can't be calculated onchain, such as lending pools rewards and so on. Don't worry about the logic to generate these merkle trees as that's handled offchain.


While doing the testing, I want you to think about:
- Testing the functionality
- Thinking of ways the functionality could fail either logically, programmatically or mathematically.
- Think security ways to make the functionality to fail, break or output something it shouldn't.

## Process
This contract is one of the most important ones in the project and I want to do it right, so let's follow a strict process here.
1. I want us to discuss all possible features that might be missing in the current implementation. Do research on what I have written already, then research what other merkle distributors do or what might be missing or not fully representing the reality needs.
2. Write me a complete file with what this contract has already in terms of requirements and what you think might be missing. I'll go to that file and edit it to agree or disagree with any of the inputs you give me. Give me space to tell you not do something, so it's explicit what should be done and what not.
3. Then we can do the implementation of that and I'll review.
4. Finally we do testing of the existing functionality plus the new one.
5. Security review, very in depth. If you find anything, write me a report and I'll review what I agree with and what not.
6. Write any changes required by the security review and finally fix any tests that might need to be addressed.
7. Last point, write some scripts that might make it easier to work with these. As in, I want to be able to generate dynamically these merkle trees, so when my team asks me about it, I can generate a fresh one for them.
