// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

import { ERC20, SimpleRewards } from "../src/SimpleRewards.sol";
import { BasicERC20 } from "./BasicERC20.sol";

// NoStakedBefore 
//   ├─ stake -> StakedBefore
//   └─ time passes -> NoStakedDuring
// 
// NoStakedDuring
//   ├─ stake -> StakedDuring
//   └─ time passes -> NoStakedAfter
// 
// NoStakedAfter
// 
// StakedBefore
//   └─ time passes -> StakedDuring
//
// StakedDuring
//   └─ time passes -> StakedAfter
//
// StakedAfter

abstract contract NoStakedBefore is PRBTest, StdCheats {

    event Staked(address user, uint256 amount);
    event Unstaked(address user, uint256 amount);
    event Claimed(address user, uint256 amount);
    event RewardsPerTokenUpdated(uint256 accumulated);
    event UserRewardsUpdated(address user, uint256 rewards, uint256 checkpoint);

    function give(ERC20 token, address to, uint256 amount) public {
        uint256 existing = token.balanceOf(to);
        deal(address(token), to, existing + amount);
    }

    function step(uint256 delta) public {
        vm.warp(block.timestamp + delta);
    }

    SimpleRewards public rewardsVault;
    ERC20 public stakingToken;
    uint256 public stakingUnit;
    uint256 public stakingAmount;
    ERC20 public rewardsToken;
    uint256 public rewardsUnit;
    uint256 totalRewards = 1000 * 1e18;
    uint256 leadTime = 1000000;
    uint256 intervalLength = 1000000;
    uint256 start;
    uint256 end;

    address user;
    address other;
    address me;

    function setUp() public virtual {

        stakingToken = new BasicERC20("Staking Token", "STK", 18);
        stakingUnit = 10 ** stakingToken.decimals();
        stakingAmount = 1e18 + 1; // Let's test rounding errors
        rewardsToken = new BasicERC20("Rewards Token", "TOK", 18);
        rewardsUnit = 10 ** rewardsToken.decimals();
        rewardsVault = new SimpleRewards(
            stakingToken,
            rewardsToken,
            start = block.timestamp + leadTime,
            end = block.timestamp + leadTime + intervalLength,
            totalRewards
        );

        user = address(1);
        other = address(2);

        vm.label(user, "user");
        vm.label(other, "other");
        vm.label(address(rewardsVault), "rewardsVault");
        vm.label(address(stakingToken), "stakingToken");
        vm.label(address(rewardsToken), "rewardsToken");

        vm.prank(user);
        stakingToken.approve(address(rewardsVault), type(uint256).max);
        give(stakingToken, user, stakingAmount * 10);

        vm.prank(other);
        stakingToken.approve(address(rewardsVault), type(uint256).max);
        give(stakingToken, other, stakingAmount * 10);

        give(rewardsToken, address(rewardsVault), totalRewards);
    }
}

contract NoStakedBeforeTest is NoStakedBefore {

    function testCalcRewardsPerTokenBefore() public {
        uint256 rate = rewardsVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 currentRPT = rewardsVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at start");

        vm.startPrank(user);
        rewardsVault.stake(1);
        currentRPT = rewardsVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at 0s");

        step(1);
        currentRPT = rewardsVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at 1s");
    }

    function testCalcUserRewardsBefore() public {
        uint256 rate = rewardsVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 currentRewards = rewardsVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at start");

        vm.startPrank(user);
        rewardsVault.stake(1);
        currentRewards = rewardsVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at 0s");

        step(1);
        currentRewards = rewardsVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at 1s");
    }

    function testStake() public {
        assertEq(stakingToken.balanceOf(user), stakingAmount * 10, "User balance is not correct");
        assertEq(stakingToken.balanceOf(other), stakingAmount * 10, "Other balance is not correct");
        assertEq(stakingToken.balanceOf(address(rewardsVault)), 0, "RewardsVault balance is not correct");

        assertEq(rewardsVault.totalStaked(), 0, "Total staked is not correct");
        assertEq(rewardsVault.userStake(user), 0, "User stake is not correct");
        assertEq(rewardsVault.userStake(other), 0, "Other stake is not correct");

        vm.prank(user);
        rewardsVault.stake(stakingAmount);
        assertEq(stakingToken.balanceOf(user), stakingAmount * 9, "User balance is not correct");
        assertEq(stakingToken.balanceOf(other), stakingAmount * 10, "Other balance is not correct");
        assertEq(stakingToken.balanceOf(address(rewardsVault)), stakingAmount, "RewardsVault balance is not correct");

        assertEq(rewardsVault.totalStaked(), stakingAmount, "Total staked is not correct");
        assertEq(rewardsVault.userStake(user), stakingAmount, "User stake is not correct");
        assertEq(rewardsVault.userStake(other), 0, "Other stake is not correct");

        vm.prank(user);
        rewardsVault.stake(stakingAmount);
        assertEq(stakingToken.balanceOf(user), stakingAmount * 8, "User balance is not correct");
        assertEq(stakingToken.balanceOf(other), stakingAmount * 10, "Other balance is not correct");
        assertEq(stakingToken.balanceOf(address(rewardsVault)), stakingAmount * 2, "RewardsVault balance is not correct");

        assertEq(rewardsVault.totalStaked(), stakingAmount * 2, "Total staked is not correct");
        assertEq(rewardsVault.userStake(user), stakingAmount * 2, "User stake is not correct");
        assertEq(rewardsVault.userStake(other), 0, "Other stake is not correct");
    }

    function testUnstakeRevertsNoStake() public {
        vm.expectRevert();
        vm.prank(user);
        rewardsVault.unstake(stakingAmount);
   
    }
}

abstract contract NoStakedDuring is NoStakedBefore {
    function setUp() public override virtual {
        super.setUp();

        vm.warp(start);
    }

    // Stake 1 wei + 1s: RPT = rate * 1e18, Rewards = rate
    // + 1s: RPT = 2 * rate * 1e18, Rewards = 2 * rate
    // Stake another wei + 1s: RPT_1 = RPT_0 + (rate / 2) * 1e18, Rewards_1 = Rewards_0 + rate
    // Other stakes 2 wei + 1s: RPT_1 = RPT_0 + (rate / 4) * 1e18, Rewards_user_1 = Rewards_user_0 + rate / 2, Rewards_other = rate / 2
    // User withdraws all: RPT_1 = RPT_0 + (rate / 4) * 1e18, Rewards_user_1 = Rewards_user_0 + rate / 2, Rewards_other_1 = Rewards_other_0 + rate / 2
    // +1s: RPT_1 = RPT_0 + (rate / 2) * 1e18, Rewards_user_1 = Rewards_user_0, Rewards_other_1 = Rewards_other_0 + rate
}

contract NoStakedDuringTest is NoStakedDuring {
    function testCalcRewardsPerToken() public {
        uint256 rate = rewardsVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 currentRPT = rewardsVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at start");

        vm.startPrank(user);
        rewardsVault.stake(1);
        currentRPT = rewardsVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at 0s");

        step(1);
        currentRPT = rewardsVault.currentRewardsPerToken();
        assertEq(currentRPT, rate * 1e18, "RPT != rate at 1s");

        uint256 beforeRPT = currentRPT;
        rewardsVault.stake(1);
        step(1);
        currentRPT = rewardsVault.currentRewardsPerToken();
        assertEq(currentRPT, beforeRPT + (rate / 2 * 1e18), "RPT != rate * 3/2 at 2s");
        vm.stopPrank();

        beforeRPT = currentRPT;
        vm.prank(other);
        rewardsVault.stake(2);
        step(1);
        currentRPT = rewardsVault.currentRewardsPerToken();
        assertEq(currentRPT, beforeRPT + (rate / 4 * 1e18), "RPT != rate * 7/4 at 3s");

        beforeRPT = currentRPT;
        vm.prank(user);
        rewardsVault.unstake(2);
        step(1);
        currentRPT = rewardsVault.currentRewardsPerToken();
        assertEq(currentRPT, beforeRPT + (rate / 2 * 1e18), "RPT != rate * 13/4 at 4s");
    }

    function testCalcUserRewards() public {
        uint256 rate = rewardsVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 currentRewards = rewardsVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at start");

        vm.startPrank(user);
        rewardsVault.stake(1);
        currentRewards = rewardsVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at 0s");

        step(1);
        currentRewards = rewardsVault.currentUserRewards(user);
        assertEq(currentRewards, rate, "UserRewards != rate at 1s");

        uint256 previousRewards = currentRewards;
        rewardsVault.stake(1);
        step(1);
        currentRewards = rewardsVault.currentUserRewards(user);
        assertEq(currentRewards, previousRewards + rate, "UserRewards != 2 * rate at 2s");
        vm.stopPrank();

        previousRewards = currentRewards;
        vm.prank(other);
        rewardsVault.stake(2);
        step(1);
        currentRewards = rewardsVault.currentUserRewards(user);
        assertEq(currentRewards, previousRewards + (rate / 2), "UserRewards != rate * 3/2 at 3s");

        previousRewards = currentRewards;
        vm.prank(user);
        rewardsVault.unstake(2);
        step(1);
        currentRewards = rewardsVault.currentUserRewards(user);
        assertEq(currentRewards, previousRewards, "UserRewards != rate * 3/2 at 4s");
    }

    function testCalcRewardsPerTokenFromMiddle() public {
        uint256 rate = rewardsVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 totalStaked = rewardsVault.totalStaked();
        assertEq(totalStaked, 0, "Total staked not zero");

        uint256 currentRPT = rewardsVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at start");

        step(intervalLength / 2);

        vm.startPrank(user);
        rewardsVault.stake(1);
        currentRPT = rewardsVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at t+0s");

        step(1);
        currentRPT = rewardsVault.currentRewardsPerToken();
        assertEq(currentRPT, rate * 1e18, "RPT != rate at t+1s");
    }

    function testCalcUserRewardsFromMiddle() public {
        uint256 rate = rewardsVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 currentRewards = rewardsVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at start");

        step(intervalLength / 2);

        vm.startPrank(user);
        rewardsVault.stake(1);
        currentRewards = rewardsVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at t+0s");

        step(1);
        currentRewards = rewardsVault.currentUserRewards(user);
        assertEq(currentRewards, rate, "UserRewards != rate at t+1s");
    }

    function testCalcRewardsPerTokenThroughEnd() public {
        uint256 rate = rewardsVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 totalStaked = rewardsVault.totalStaked();
        assertEq(totalStaked, 0, "Total staked not zero");

        uint256 currentRPT = rewardsVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at start");

        vm.startPrank(user);
        rewardsVault.stake(1e18);

        step(intervalLength * 2);

        currentRPT = rewardsVault.currentRewardsPerToken();
        assertEq(currentRPT, rate * intervalLength, "RPT != rate * intervalLength"); // RPT = rate * intervalLength * 1e18 / totalStaked
    }

    function testCalcUserRewardsThroughEnd() public {
        uint256 rate = rewardsVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 totalStaked = rewardsVault.totalStaked();
        assertEq(totalStaked, 0, "Total staked not zero");

        uint256 currentRewards = rewardsVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero");

        vm.startPrank(user);
        rewardsVault.stake(1e18);

        step(intervalLength * 2);

        currentRewards = rewardsVault.currentUserRewards(user);
        assertEq(currentRewards, totalRewards, "UserRewards != TotalRewards after end");
    }
}

abstract contract NoStakedAfter is NoStakedDuring {
    function setUp() public override virtual {
        super.setUp();

        vm.warp(end);
    }
}

contract NoStakedAfterTest is NoStakedAfter {

    function testCalcRewardsPerTokenAfter() public {
        uint256 rate = rewardsVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 currentRPT = rewardsVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at start");

        vm.startPrank(user);
        rewardsVault.stake(1e18); // If we stake a single wei we get RPT = rate * intervalLength * 1e18 > type(uint128).max
        currentRPT = rewardsVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at 0s");

        step(1);
        currentRPT = rewardsVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at 1s");
    }

    function testCalcUserRewardsAfter() public {
        uint256 rate = rewardsVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 currentRewards = rewardsVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at start");

        vm.startPrank(user);
        rewardsVault.stake(1e18);
        currentRewards = rewardsVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at 0s");

        step(1);
        currentRewards = rewardsVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at 1s");
    }
}

abstract contract StakedBefore is NoStakedBefore {
    function setUp() public override virtual {
        super.setUp();

        vm.prank(user);
        rewardsVault.stake(stakingAmount);
    }
}

contract StakedBeforeTest is StakedBefore {
    function testUnstake() public {
        assertEq(rewardsVault.totalStaked(), stakingAmount, "Total staked is not correct");
        assertEq(rewardsVault.userStake(user), stakingAmount, "User stake is not correct");
        assertEq(rewardsVault.userStake(other), 0, "Other stake is not correct");

        uint256 unstakingAmount = stakingAmount / 2;

        vm.prank(user);
        rewardsVault.unstake(unstakingAmount);
        assertEq(stakingToken.balanceOf(user), stakingAmount * 9 + unstakingAmount, "User balance is not correct");
        assertEq(stakingToken.balanceOf(other), stakingAmount * 10, "Other balance is not correct");
        assertEq(stakingToken.balanceOf(address(rewardsVault)), stakingAmount - unstakingAmount, "RewardsVault balance is not correct");

        assertEq(rewardsVault.totalStaked(), stakingAmount - unstakingAmount, "Total staked is not correct");
        assertEq(rewardsVault.userStake(user), stakingAmount - unstakingAmount, "User stake is not correct");
        assertEq(rewardsVault.userStake(other), 0, "Other stake is not correct");

        unstakingAmount = rewardsVault.userStake(user);
        vm.prank(user);
        rewardsVault.unstake(unstakingAmount);
        assertEq(stakingToken.balanceOf(user), stakingAmount * 10, "User balance is not correct");
        assertEq(stakingToken.balanceOf(other), stakingAmount * 10, "Other balance is not correct");
        assertEq(stakingToken.balanceOf(address(rewardsVault)), 0, "RewardsVault balance is not correct");

        assertEq(rewardsVault.totalStaked(), 0, "Total staked is not correct");
        assertEq(rewardsVault.userStake(user), 0, "User stake is not correct");
        assertEq(rewardsVault.userStake(other), 0, "Other stake is not correct");
    }
}

abstract contract StakedDuring is StakedBefore {
    function setUp() public override virtual {
        super.setUp();

        vm.warp(start);
    }
}

abstract contract StakedAfter is StakedDuring {
    function setUp() public override virtual {
        super.setUp();

        vm.warp(end);
    }
}

contract StakedAfterTest is StakedAfter {

    function testClaim() public {
        assertEq(rewardsToken.balanceOf(user), 0, "User balance is not correct");
        assertEq(rewardsToken.balanceOf(other), 0, "Other balance is not correct");
        assertEq(rewardsToken.balanceOf(address(rewardsVault)), totalRewards, "RewardsVault balance is not correct");
        assertEq(rewardsVault.currentUserRewards(user), totalRewards - 1, "User rewards is not correct");

        vm.prank(user);
        rewardsVault.claim();
        assertEq(rewardsToken.balanceOf(user), totalRewards - 1, "User balance is not correct");
        assertEq(rewardsToken.balanceOf(other), 0, "Other balance is not correct");
        assertEq(rewardsToken.balanceOf(address(rewardsVault)), 1, "RewardsVault balance is not correct");
        assertEq(rewardsVault.currentUserRewards(user), 0, "User rewards is not correct");
    }
}

