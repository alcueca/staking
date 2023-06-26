// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { ERC20 } from "../lib/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "../lib/solmate/src/utils/SafeTransferLib.sol";
import { Cast } from "../lib/yield-utils-v2/src/utils/Cast.sol";


/// @notice Permissionless staking contract for a single rewards program.
/// From the start of the program, to the end of the program, a fixed amount of rewards tokens will be distributed among stakers.
/// The rate at which rewards are distributed is constant over time, but proportional to the amount of tokens staked by each staker.
/// The contract expects to have received enough rewards tokens by the time they are claimable. The rewards tokens can only be recovered by claiming stakers.
/// This is a rewriting of [Unipool.sol](https://github.com/k06a/Unipool/blob/master/contracts/Unipool.sol), modified for clarity and simplified.
contract SimpleRewards {
    using SafeTransferLib for ERC20;
    using Cast for uint256;

    event Staked(address user, uint256 amount);
    event Unstaked(address user, uint256 amount);
    event Claimed(address user, uint256 amount);
    event RewardsPerTokenUpdated(uint256 accumulated);
    event UserRewardsUpdated(address user, uint256 rewards, uint256 checkpoint);

    struct RewardsInterval {
        uint32 start;
        uint32 end;
    }

    struct RewardsPerToken {
        uint128 accumulated;                                        // Accumulated rewards per token for the interval, scaled up by 1e18
        uint32 lastUpdated;                                         // Last time the rewards per token accumulator was updated
    }

    struct UserRewards {
        uint128 accumulated;                                        // Accumulated rewards for the user until the checkpoint
        uint128 checkpoint;                                         // RewardsPerToken the last time the user rewards were updated
    }

    ERC20 public immutable stakingToken;                           // Token to be staked
    uint256 public totalStaked;                                     // Total amount staked
    mapping (address => uint256) public userStake;                  // Amount staked per user

    ERC20 public immutable rewardsToken;                           // Token used as rewards
    uint256 public immutable rate;                                  // Wei rewarded per second among all token holders         
    RewardsInterval public rewardsInterval;                         // Interval in which rewards are accumulated by users
    RewardsPerToken public rewardsPerToken;                         // Accumulator to track rewards per token
    mapping (address => UserRewards) public accumulatedRewards;     // Rewards accumulated per user
    
    constructor(ERC20 stakingToken_, ERC20 rewardsToken_, uint256 start, uint256 end, uint256 totalRewards)
    {
        stakingToken = stakingToken_;
        rewardsToken = rewardsToken_;
        rewardsInterval.start = start.u32();
        rewardsInterval.end = end.u32();
        rewardsPerToken.lastUpdated = start.u32();
        rate = totalRewards / (end - start);    
    }

    /// @notice Update the rewards per token accumulator according to the rate, the time elapsed since the last update, and the current total staked amount.
    function _calculateRewardsPerToken(RewardsPerToken memory rewardsPerToken_, RewardsInterval memory rewardsInterval_) internal view returns(RewardsPerToken memory) {
        // We skip the update if the program hasn't started
        if (block.timestamp < rewardsInterval_.start) return rewardsPerToken_;

        // We stop updating at the end of the rewards interval
        uint256 updateTime = block.timestamp < rewardsInterval_.end ? block.timestamp : rewardsInterval_.end;

        // We skip the storage changes if already updated in the same block, or if the program has ended and was updated at the end
        if (rewardsPerToken_.lastUpdated == updateTime) return rewardsPerToken_;

        // Calculate and update the new value of the accumulator.
        uint256 elapsed = updateTime - rewardsPerToken_.lastUpdated;
        rewardsPerToken_.accumulated = (rewardsPerToken_.accumulated + 1e18 * elapsed * rate  / totalStaked).u128(); // The rewards per token are scaled up for precision
        rewardsPerToken_.lastUpdated = updateTime.u32();
        return rewardsPerToken_;
    }

    /// @notice Calculate the rewards accumulated by a stake between two checkpoints.
    function _calculateUserRewards(uint256 stake_, uint256 earlierCheckpoint, uint256 latterCheckpoint) internal pure returns (uint256) {
        return stake_ * (latterCheckpoint - earlierCheckpoint) / 1e18; // We must scale down the rewards by the precision factor
    }

    /// @notice Update and return the rewards per token accumulator according to the rate, the time elapsed since the last update, and the current total staked amount.
    function _updateRewardsPerToken() internal returns (RewardsPerToken memory){
        RewardsPerToken memory rewardsPerToken_ = _calculateRewardsPerToken(rewardsPerToken, rewardsInterval);
        rewardsPerToken = rewardsPerToken_;
        emit RewardsPerTokenUpdated(rewardsPerToken_.accumulated);

        return rewardsPerToken_;
    }

    /// @notice Calculate and store current rewards for an user. Checkpoint the rewardsPerToken value with the user.
    function _updateUserRewards(address user) internal returns (UserRewards memory) {
        RewardsPerToken memory rewardsPerToken_ = _updateRewardsPerToken();
        UserRewards memory userRewards_ = accumulatedRewards[user];
        
        // Calculate and update the new value user reserves.
        userRewards_.accumulated += _calculateUserRewards(userStake[user], userRewards_.checkpoint, rewardsPerToken_.accumulated).u128();
        userRewards_.checkpoint = rewardsPerToken_.accumulated;
        accumulatedRewards[user] = userRewards_;
        emit UserRewardsUpdated(user, userRewards_.accumulated, userRewards_.checkpoint);

        return userRewards_;
    }

    /// @notice Stake tokens.
    function _stake(address user, uint256 amount) internal
    {
        _updateUserRewards(user);
        totalStaked += amount;
        userStake[user] += amount;
        stakingToken.safeTransferFrom(user, address(this), amount);
        emit Staked(user, amount);
    }


    /// @notice Unstake tokens.
    function _unstake(address user, uint256 amount) internal
    {
        _updateUserRewards(user);
        totalStaked -= amount;
        userStake[user] -= amount;
        stakingToken.safeTransfer(user, amount);
        emit Unstaked(user, amount);
    }

    /// @notice Claim rewards.
    function _claim(address user, uint256 amount) internal
    {
        uint256 rewardsAvailable = _updateUserRewards(msg.sender).accumulated;
        
        // This line would panic if the user doesn't have enough rewards accumulated
        accumulatedRewards[user].accumulated = (rewardsAvailable - amount).u128();

        // This line would panic if the contract doesn't have enough rewards tokens
        rewardsToken.safeTransfer(user, amount);
        emit Claimed(user, amount);
    }


    /// @notice Stake tokens.
    function stake(uint256 amount) public virtual
    {
        _stake(msg.sender, amount);
    }


    /// @notice Unstake tokens.
    function unstake(uint256 amount) public virtual
    {
        _unstake(msg.sender, amount);
    }

    /// @notice Claim all rewards for the caller.
    function claim() public virtual returns (uint256)
    {
        uint256 claimed = _updateUserRewards(msg.sender).accumulated;
        _claim(msg.sender, claimed);
        return claimed;
    }

    /// @notice Calculate and return current rewards per token.
    function currentRewardsPerToken() public view returns (uint256) {
        return _calculateRewardsPerToken(rewardsPerToken, rewardsInterval).accumulated;
    }

    /// @notice Calculate and return current rewards for a user.
    /// @dev This repeats the logic used on transactions, but doesn't update the storage.
    function currentUserRewards(address user) public view returns (uint256) {
        UserRewards memory accumulatedRewards_ = accumulatedRewards[user];
        RewardsPerToken memory rewardsPerToken_ = _calculateRewardsPerToken(rewardsPerToken, rewardsInterval);
        return accumulatedRewards_.accumulated + _calculateUserRewards(userStake[user], accumulatedRewards_.checkpoint, rewardsPerToken_.accumulated);
    }
}
