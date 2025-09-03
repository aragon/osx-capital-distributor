// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.29;

/// @notice Mock token that returns false instead of reverting on failed transfers
/// @dev Used to test token validation in CapitalDistributorPlugin
contract BadERC20Mock {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    string public name = "Bad Token";
    string public symbol = "BAD";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    // Transfer always returns false (doesn't revert)
    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    // TransferFrom always returns false (doesn't revert)
    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }

    // Approve works normally (for completeness)
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    // Mint function for testing
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}
