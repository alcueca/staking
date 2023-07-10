// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;


import { ERC20 } from "../src/SimpleRewards.sol";

contract BasicERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_, decimals_) {}
}