// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

import { ERC20, ERC20Rewards } from "../src/ERC20Rewards.sol";
import { MintableERC20Rewards } from "./MintableERC20Rewards.sol";
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

abstract contract Deployed is PRBTest, StdCheats {

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

    MintableERC20Rewards public stakingVault;
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

    function setUp() public virtual {

        rewardsToken = new BasicERC20("Rewards Token", "TOK", 18);
        rewardsUnit = 10 ** rewardsToken.decimals();
        stakingVault = new MintableERC20Rewards(
            address(this),
            rewardsToken,
            "Staking Token",
            "STK",
            18
        );
        stakingUnit = 10 ** stakingVault.decimals();
        stakingAmount = 1e18 + 1; // Let's test rounding errors

        user = address(1);
        other = address(2);

        vm.label(user, "user");
        vm.label(other, "other");
        vm.label(address(stakingVault), "stakingVault");
        vm.label(address(rewardsToken), "rewardsToken");

        give(rewardsToken, address(stakingVault), totalRewards);
    }
}

contract DeployedTest is Deployed {
    function testSetInterval() public {
        start = block.timestamp + leadTime;
        end = start + intervalLength;

        stakingVault.setRewardsInterval(start, end, totalRewards);

        // assertEq((stakingVault.rewardsInterval()).start, start, "Start is not correct");
        // assertEq((stakingVault.rewardsInterval()).end, end, "End is not correct");  
        // assertEq((stakingVault.rewardsPerToken()).rate, 1e15, "Rate is not correct");  
    }
}

abstract contract NoStakedBefore is Deployed {
    function setUp() public override virtual {
        super.setUp();

        start = block.timestamp + leadTime;
        end = start + intervalLength;

        stakingVault.setRewardsInterval(start, end, totalRewards);
    }
}

contract NoStakedBeforeTest is NoStakedBefore {

    function testCalcRewardsPerTokenBefore() public {
        uint256 rate = stakingVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 currentRPT = stakingVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at start");

        vm.startPrank(user);
        stakingVault.mint(1);
        currentRPT = stakingVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at 0s");

        step(1);
        currentRPT = stakingVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at 1s");
    }

    function testCalcUserRewardsBefore() public {
        uint256 rate = stakingVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 currentRewards = stakingVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at start");

        vm.startPrank(user);
        stakingVault.mint(1);
        currentRewards = stakingVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at 0s");

        step(1);
        currentRewards = stakingVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at 1s");
    }

    function testMint() public {
        assertEq(stakingVault.totalSupply(), 0, "Total supply is not correct");
        assertEq(stakingVault.balanceOf(user), 0, "User balance is not correct");
        assertEq(stakingVault.balanceOf(other), 0, "Other balance is not correct");

        vm.prank(user);
        stakingVault.mint(stakingAmount);
        assertEq(stakingVault.totalSupply(), stakingAmount, "Total supply is not correct");
        assertEq(stakingVault.balanceOf(user), stakingAmount, "User balance is not correct");
        assertEq(stakingVault.balanceOf(other), 0, "Other balance is not correct");

        vm.prank(user);
        stakingVault.mint(stakingAmount);
        assertEq(stakingVault.totalSupply(), stakingAmount * 2, "Total supply is not correct");
        assertEq(stakingVault.balanceOf(user), stakingAmount * 2, "User balance is not correct");
        assertEq(stakingVault.balanceOf(other), 0, "Other balance is not correct");
    }

    function testBurnRevertsNoStake() public {
        vm.expectRevert();
        vm.prank(user);
        stakingVault.burn(stakingAmount);
   
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
    // Other balances 2 wei + 1s: RPT_1 = RPT_0 + (rate / 4) * 1e18, Rewards_user_1 = Rewards_user_0 + rate / 2, Rewards_other = rate / 2
    // User withdraws all: RPT_1 = RPT_0 + (rate / 4) * 1e18, Rewards_user_1 = Rewards_user_0 + rate / 2, Rewards_other_1 = Rewards_other_0 + rate / 2
    // +1s: RPT_1 = RPT_0 + (rate / 2) * 1e18, Rewards_user_1 = Rewards_user_0, Rewards_other_1 = Rewards_other_0 + rate
}

contract NoStakedDuringTest is NoStakedDuring {
    function testCalcRewardsPerToken() public {
        uint256 rate = stakingVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 currentRPT = stakingVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at start");

        vm.startPrank(user);
        stakingVault.mint(1);
        currentRPT = stakingVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at 0s");

        step(1);
        currentRPT = stakingVault.currentRewardsPerToken();
        assertEq(currentRPT, rate * 1e18, "RPT != rate at 1s");

        uint256 beforeRPT = currentRPT;
        stakingVault.mint(1);
        step(1);
        currentRPT = stakingVault.currentRewardsPerToken();
        assertEq(currentRPT, beforeRPT + (rate / 2 * 1e18), "RPT != rate * 3/2 at 2s");
        vm.stopPrank();

        beforeRPT = currentRPT;
        vm.prank(user);
        stakingVault.transfer(other, 2);
        step(1);
        currentRPT = stakingVault.currentRewardsPerToken();
        assertEq(currentRPT, beforeRPT + (rate / 2 * 1e18), "RPT != rate * 5/2 at 3s");

        beforeRPT = currentRPT;
        vm.prank(other);
        stakingVault.burn(2);
        step(1);
        currentRPT = stakingVault.currentRewardsPerToken();
        assertEq(currentRPT, beforeRPT, "RPT != rate * 5/2 at 4s");
    }

    function testCalcUserRewards() public {
        uint256 rate = stakingVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 currentRewards = stakingVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at start");

        vm.startPrank(user);
        stakingVault.mint(1);
        currentRewards = stakingVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at 0s");

        step(1);
        currentRewards = stakingVault.currentUserRewards(user);
        assertEq(currentRewards, rate, "UserRewards != rate at 1s");

        uint256 previousRewards = currentRewards;
        stakingVault.mint(1);
        step(1);
        currentRewards = stakingVault.currentUserRewards(user);
        assertEq(currentRewards, previousRewards + rate, "UserRewards != 2 * rate at 2s");
        vm.stopPrank();

        previousRewards = currentRewards;
        vm.prank(user);
        stakingVault.transfer(other, 1);
        step(1);
        currentRewards = stakingVault.currentUserRewards(user);
        assertEq(stakingVault.currentUserRewards(user), previousRewards + (rate / 2), "UserRewards != rate * 5/2 at 3s");
        assertEq(stakingVault.currentUserRewards(other), (rate / 2), "OtherRewards != rate * 1/2 at 3s");

        previousRewards = stakingVault.currentUserRewards(other);
        vm.prank(other);
        stakingVault.burn(1);
        step(1);
        currentRewards = stakingVault.currentUserRewards(other);
        assertEq(currentRewards, previousRewards, "OtherRewards != rate * 1/2 at 4s");
    }

    function testCalcRewardsPerTokenFromMiddle() public {
        uint256 rate = stakingVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 totalStaked = stakingVault.totalSupply();
        assertEq(totalStaked, 0, "Total supply not zero");

        uint256 currentRPT = stakingVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at start");

        step(intervalLength / 2);

        vm.startPrank(user);
        stakingVault.mint(1);
        currentRPT = stakingVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at t+0s");

        step(1);
        currentRPT = stakingVault.currentRewardsPerToken();
        assertEq(currentRPT, rate * 1e18, "RPT != rate at t+1s");
    }

    function testCalcUserRewardsFromMiddle() public {
        uint256 rate = stakingVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 currentRewards = stakingVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at start");

        step(intervalLength / 2);

        vm.startPrank(user);
        stakingVault.mint(1);
        currentRewards = stakingVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at t+0s");

        step(1);
        currentRewards = stakingVault.currentUserRewards(user);
        assertEq(currentRewards, rate, "UserRewards != rate at t+1s");
    }

    function testCalcRewardsPerTokenThroughEnd() public {
        uint256 rate = stakingVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 totalStaked = stakingVault.totalSupply();
        assertEq(totalStaked, 0, "Total supply not zero");

        uint256 currentRPT = stakingVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at start");

        vm.startPrank(user);
        stakingVault.mint(1e18);

        step(intervalLength * 2);

        currentRPT = stakingVault.currentRewardsPerToken();
        assertEq(currentRPT, rate * intervalLength, "RPT != rate * intervalLength"); // RPT = rate * intervalLength * 1e18 / totalStaked
    }

    function testCalcUserRewardsThroughEnd() public {
        uint256 rate = stakingVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 totalStaked = stakingVault.totalSupply();
        assertEq(totalStaked, 0, "Total supply not zero");

        uint256 currentRewards = stakingVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero");

        vm.startPrank(user);
        stakingVault.mint(1e18);

        step(intervalLength * 2);

        currentRewards = stakingVault.currentUserRewards(user);
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
        uint256 rate = stakingVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 currentRPT = stakingVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at start");

        vm.startPrank(user);
        stakingVault.mint(1e18); // If we stake a single wei we get RPT = rate * intervalLength * 1e18 > type(uint128).max
        currentRPT = stakingVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at 0s");

        step(1);
        currentRPT = stakingVault.currentRewardsPerToken();
        assertEq(currentRPT, 0, "RPT != zero at 1s");
    }

    function testCalcUserRewardsAfter() public {
        uint256 rate = stakingVault.rate();
        assertNotEq(rate, 0, "Rate is zero");

        uint256 currentRewards = stakingVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at start");

        vm.startPrank(user);
        stakingVault.mint(1e18);
        currentRewards = stakingVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at 0s");

        step(1);
        currentRewards = stakingVault.currentUserRewards(user);
        assertEq(currentRewards, 0, "UserRewards != zero at 1s");
    }
}

abstract contract StakedBefore is NoStakedBefore {
    function setUp() public override virtual {
        super.setUp();

        vm.prank(user);
        stakingVault.mint(stakingAmount);
    }
}

contract StakedBeforeTest is StakedBefore {
    function testBurn() public {
        assertEq(stakingVault.totalSupply(), stakingAmount, "Total supply is not correct");
        assertEq(stakingVault.balanceOf(user), stakingAmount, "User balance is not correct");
        assertEq(stakingVault.balanceOf(other), 0, "Other balance is not correct");

        uint256 unstakingAmount = stakingAmount / 2;

        vm.prank(user);
        stakingVault.burn(unstakingAmount);

        assertEq(stakingVault.totalSupply(), stakingAmount - unstakingAmount, "Total supply is not correct");
        assertEq(stakingVault.balanceOf(user), stakingAmount - unstakingAmount, "User balance is not correct");
        assertEq(stakingVault.balanceOf(other), 0, "Other balance is not correct");

        unstakingAmount = stakingVault.balanceOf(user);

        vm.prank(user);
        stakingVault.burn(unstakingAmount);

        assertEq(stakingVault.totalSupply(), 0, "Total supply is not correct");
        assertEq(stakingVault.balanceOf(user), 0, "User balance is not correct");
        assertEq(stakingVault.balanceOf(other), 0, "Other balance is not correct");
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
        assertEq(rewardsToken.balanceOf(address(stakingVault)), totalRewards, "StakingVault balance is not correct");
        assertEq(stakingVault.currentUserRewards(user), totalRewards - 1, "User rewards is not correct");

        vm.prank(user);
        stakingVault.claim(user);
        assertEq(rewardsToken.balanceOf(user), totalRewards - 1, "User balance is not correct");
        assertEq(rewardsToken.balanceOf(other), 0, "Other balance is not correct");
        assertEq(rewardsToken.balanceOf(address(stakingVault)), 1, "StakingVault balance is not correct");
        assertEq(stakingVault.currentUserRewards(user), 0, "User rewards is not correct");
    }
}

