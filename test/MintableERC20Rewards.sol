// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;


import { ERC20, ERC20Rewards } from "../src/ERC20Rewards.sol";

contract MintableERC20Rewards is ERC20Rewards {
    constructor(address owner, ERC20 rewardsToken, string memory name_, string memory symbol_, uint8 decimals_)
        ERC20Rewards(owner, rewardsToken, name_, symbol_, decimals_) {}

    /// @notice Helper to access the rate
    function rate() public view returns (uint256) {
        return rewardsPerToken.rate;
    }

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}