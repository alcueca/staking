# Rewards Contracts

Smart contracts to build staking and reward solutions.

## What's Inside

- [SimpleRewards](./src/SimpleRewards.sol): Single-use permissionless staking for rewards.
- [ERC20Rewards](./src/ERC20Rewards.sol): ERC20 with rewards for holding.
- [ERC4626Rewards](./src/ERC4626Rewards.sol): ERC4626 with rewards for depositing.
- [ReplaceableRewardsToken](./src/ReplaceableRewardsToken.sol): Wrapper to allow replacing the rewards token in ERC20Rewards or ERC4626Rewards

## Safety

This is **experimental software** and is provided on an "as is" and "as available" basis. While the building blocks for these contracts (solmate and yield-utils-v2) have been audited, the combination in this repository hasn't. Please arrange the appropriate security measures for your own use of these contracts.

We **do not give any warranties** and **will not be liable for any loss** incurred through any use of this codebase.

## Installation

To install with [**Foundry**](https://github.com/gakonst/foundry):

```sh
forge install alcueca/staking
```


## Acknowledgements

These contracts were inspired by or directly modified from two sources:

- [Yield](https://github.com/yieldprotocol/yield-utils-v2)
- [Solmate](https://github.com/transmissions11/solmate)

Thanks to Paul Berg for the template used for this repository.
- [PRB Foundry Template](https://github.com/PaulRBerg/foundry-template)

## License

This project is licensed under AGPL-3.0.
