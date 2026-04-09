// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {StakingMultiRewards} from "../src/StakingMultiRewards.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StakingMultiRewardsTest is Test {
    StakingMultiRewards public staking;
    ERC20Mock public stakingToken;
    ERC20Mock public rewardTokenA;
    ERC20Mock public rewardTokenB;
    ERC20Mock public randomToken;

    address constant OWNER = address(0xA11CE);
    address constant DISTRIBUTOR = address(0xD157);
    address constant ALICE = address(0xA1);
    address constant BOB = address(0xB0B);
    address constant CAROL = address(0xCA01);

    uint256 constant DURATION = 7 days;
    uint256 constant REWARD = 604_800e18;
    uint256 constant STAKE = 100e18;
    uint256 constant WAD = 1e18;

    function setUp() public {
        stakingToken = new ERC20Mock();
        rewardTokenA = new ERC20Mock();
        rewardTokenB = new ERC20Mock();
        randomToken = new ERC20Mock();

        staking = new StakingMultiRewards(OWNER, IERC20(address(stakingToken)), DISTRIBUTOR);

        vm.prank(OWNER);
        staking.addRewardToken(address(rewardTokenA), DURATION);

        stakingToken.mint(ALICE, 1_000_000e18);
        stakingToken.mint(BOB, 1_000_000e18);
        stakingToken.mint(CAROL, 1_000_000e18);

        vm.prank(ALICE);
        stakingToken.approve(address(staking), type(uint256).max);
        vm.prank(BOB);
        stakingToken.approve(address(staking), type(uint256).max);
        vm.prank(CAROL);
        stakingToken.approve(address(staking), type(uint256).max);
    }

    function _notify(address token, uint256 amount) internal {
        ERC20Mock(token).mint(address(staking), amount);
        vm.prank(DISTRIBUTOR);
        staking.notifyRewardAmount(token, amount);
    }

    function _addTokenB() internal {
        vm.prank(OWNER);
        staking.addRewardToken(address(rewardTokenB), DURATION);
    }

    /* ========== CONSTRUCTOR ========== */

    function test_constructor_setsState() public view {
        assertEq(address(staking.stakingToken()), address(stakingToken));
        assertEq(staking.rewardsDistribution(), DISTRIBUTOR);
        assertEq(staking.owner(), OWNER);
        assertEq(staking.totalSupply(), 0);
    }

    function test_constructor_revertsOnZeroStakingToken() public {
        vm.expectRevert("_stakingToken can't be address(0)");
        new StakingMultiRewards(OWNER, IERC20(address(0)), DISTRIBUTOR);
    }

    function test_constructor_revertsOnZeroDistributor() public {
        vm.expectRevert("_rewardsDistribution can't be address(0)");
        new StakingMultiRewards(OWNER, IERC20(address(stakingToken)), address(0));
    }

    /* ========== ADD REWARD TOKEN ========== */

    function test_addRewardToken_success() public {
        _addTokenB();
        assertEq(staking.getRewardsTokensCount(), 2);
        assertTrue(staking.isRewardsToken(address(rewardTokenB)));
        assertEq(staking.rewardsDuration(address(rewardTokenB)), DURATION);
    }

    function test_addRewardToken_emitsEvent() public {
        vm.prank(OWNER);
        vm.expectEmit(true, false, false, true);
        emit StakingMultiRewards.RewardTokenAdded(address(rewardTokenB), DURATION);
        staking.addRewardToken(address(rewardTokenB), DURATION);
    }

    function test_addRewardToken_revertsIfAlreadyAdded() public {
        vm.prank(OWNER);
        vm.expectRevert("rewardToken already added");
        staking.addRewardToken(address(rewardTokenA), DURATION);
    }

    function test_addRewardToken_revertsIfZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert("rewardToken can't be address(0)");
        staking.addRewardToken(address(0), DURATION);
    }

    function test_addRewardToken_revertsIfZeroDuration() public {
        vm.prank(OWNER);
        vm.expectRevert("stream rewards atleast a second");
        staking.addRewardToken(address(rewardTokenB), 0);
    }

    function test_addRewardToken_revertsIfNotOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        staking.addRewardToken(address(rewardTokenB), DURATION);
    }

    /* ========== VIEW FUNCTIONS ========== */

    function test_getRewardsTokens_returnsAll() public {
        _addTokenB();
        address[] memory tokens = staking.getRewardsTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(rewardTokenA));
        assertEq(tokens[1], address(rewardTokenB));
    }

    function test_getRewardsToken_revertsOutOfBounds() public {
        vm.expectRevert();
        staking.getRewardsToken(99);
    }

    function test_isRewardsToken_falseForUnregistered() public view {
        assertFalse(staking.isRewardsToken(address(randomToken)));
    }

    function test_lastTimeRewardApplicable_zeroBeforeNotify() public view {
        assertEq(staking.lastTimeRewardApplicable(address(rewardTokenA)), 0);
    }

    function test_lastTimeRewardApplicable_duringPeriod() public {
        _notify(address(rewardTokenA), REWARD);
        skip(1 days);
        assertEq(staking.lastTimeRewardApplicable(address(rewardTokenA)), block.timestamp);
    }

    function test_lastTimeRewardApplicable_afterPeriod() public {
        _notify(address(rewardTokenA), REWARD);
        uint256 finish = staking.periodFinish(address(rewardTokenA));
        skip(8 days);
        assertEq(staking.lastTimeRewardApplicable(address(rewardTokenA)), finish);
    }

    function test_rewardPerToken_zeroWhenNoSupply() public {
        _notify(address(rewardTokenA), REWARD);
        skip(1 days);
        assertEq(staking.rewardPerToken(address(rewardTokenA)), 0);
    }

    function test_earned_zeroForNonStaker() public {
        _notify(address(rewardTokenA), REWARD);
        vm.prank(ALICE);
        staking.stake(STAKE);
        skip(1 days);
        assertEq(staking.earned(BOB, address(rewardTokenA)), 0);
    }

    function test_getRewardForDuration_exactForCleanNumbers() public {
        _notify(address(rewardTokenA), REWARD);
        assertEq(staking.getRewardForDuration(address(rewardTokenA)), REWARD);
    }

    /* ========== STAKE ========== */

    function test_stake_updatesState() public {
        vm.prank(ALICE);
        staking.stake(STAKE);

        assertEq(staking.totalSupply(), STAKE);
        assertEq(staking.balances(ALICE), STAKE);
        assertEq(stakingToken.balanceOf(address(staking)), STAKE);
    }

    function test_stake_emitsEvent() public {
        vm.prank(ALICE);
        vm.expectEmit(true, false, false, true);
        emit StakingMultiRewards.Staked(ALICE, STAKE);
        staking.stake(STAKE);
    }

    function test_stake_revertsOnZero() public {
        vm.prank(ALICE);
        vm.expectRevert("Cannot stake 0");
        staking.stake(0);
    }

    function test_stake_revertsWhenPaused() public {
        vm.prank(OWNER);
        staking.pause();
        vm.prank(ALICE);
        vm.expectRevert();
        staking.stake(STAKE);
    }

    function test_stake_multipleUsers() public {
        vm.prank(ALICE);
        staking.stake(STAKE);
        vm.prank(BOB);
        staking.stake(STAKE / 2);

        assertEq(staking.totalSupply(), STAKE + STAKE / 2);
        assertEq(staking.balances(ALICE), STAKE);
        assertEq(staking.balances(BOB), STAKE / 2);
    }

    /* ========== WITHDRAW ========== */

    function test_withdraw_full() public {
        vm.prank(ALICE);
        staking.stake(STAKE);
        vm.prank(ALICE);
        staking.withdraw(STAKE);

        assertEq(staking.totalSupply(), 0);
        assertEq(staking.balances(ALICE), 0);
        assertEq(stakingToken.balanceOf(ALICE), 1_000_000e18);
    }

    function test_withdraw_partial() public {
        vm.prank(ALICE);
        staking.stake(STAKE);
        vm.prank(ALICE);
        staking.withdraw(STAKE / 2);

        assertEq(staking.balances(ALICE), STAKE / 2);
        assertEq(staking.totalSupply(), STAKE / 2);
    }

    function test_withdraw_revertsOnZero() public {
        vm.prank(ALICE);
        vm.expectRevert("Cannot withdraw 0");
        staking.withdraw(0);
    }

    function test_withdraw_revertsOnUnderflow() public {
        vm.prank(ALICE);
        staking.stake(STAKE);
        vm.prank(ALICE);
        vm.expectRevert();
        staking.withdraw(STAKE + 1);
    }

    function test_withdraw_doesNotTransferRewards() public {
        _notify(address(rewardTokenA), REWARD);
        vm.prank(ALICE);
        staking.stake(STAKE);
        skip(1 days);

        vm.prank(ALICE);
        staking.withdraw(STAKE);

        assertEq(rewardTokenA.balanceOf(ALICE), 0);
        assertTrue(staking.earned(ALICE, address(rewardTokenA)) > 0);
    }

    function test_withdraw_allowedWhenPaused() public {
        vm.prank(ALICE);
        staking.stake(STAKE);
        vm.prank(OWNER);
        staking.pause();
        vm.prank(ALICE);
        staking.withdraw(STAKE);
        assertEq(staking.balances(ALICE), 0);
    }

    /* ========== GET REWARD ========== */

    function test_getReward_claimsSingleToken() public {
        _notify(address(rewardTokenA), REWARD);
        vm.prank(ALICE);
        staking.stake(STAKE);
        skip(1 days);

        uint256 expected = staking.earned(ALICE, address(rewardTokenA));
        vm.prank(ALICE);
        staking.getReward(address(rewardTokenA));

        assertEq(rewardTokenA.balanceOf(ALICE), expected);
        assertEq(staking.earned(ALICE, address(rewardTokenA)), 0);
    }

    function test_getReward_noopWhenZero() public {
        vm.prank(ALICE);
        staking.getReward(address(rewardTokenA));
        assertEq(rewardTokenA.balanceOf(ALICE), 0);
    }

    function test_getReward_allowedWhenPaused() public {
        _notify(address(rewardTokenA), REWARD);
        vm.prank(ALICE);
        staking.stake(STAKE);
        skip(1 days);
        vm.prank(OWNER);
        staking.pause();

        vm.prank(ALICE);
        staking.getReward(address(rewardTokenA));
        assertTrue(rewardTokenA.balanceOf(ALICE) > 0);
    }

    function test_getReward_emitsEvent() public {
        _notify(address(rewardTokenA), REWARD);
        vm.prank(ALICE);
        staking.stake(STAKE);
        skip(1 days);

        uint256 expected = staking.earned(ALICE, address(rewardTokenA));
        vm.prank(ALICE);
        vm.expectEmit(true, true, false, true);
        emit StakingMultiRewards.RewardPaid(ALICE, address(rewardTokenA), expected);
        staking.getReward(address(rewardTokenA));
    }

    function test_getAllRewards_claimsMultipleTokens() public {
        _addTokenB();
        _notify(address(rewardTokenA), REWARD);
        _notify(address(rewardTokenB), REWARD * 2);

        vm.prank(ALICE);
        staking.stake(STAKE);
        skip(1 days);

        vm.prank(ALICE);
        staking.getAllRewards();

        assertTrue(rewardTokenA.balanceOf(ALICE) > 0);
        assertTrue(rewardTokenB.balanceOf(ALICE) > 0);
        assertEq(staking.earned(ALICE, address(rewardTokenA)), 0);
        assertEq(staking.earned(ALICE, address(rewardTokenB)), 0);
    }

    function test_getAllRewards_noopWhenNothingEarned() public {
        vm.prank(ALICE);
        staking.getAllRewards();
        assertEq(rewardTokenA.balanceOf(ALICE), 0);
    }

    /* ========== EXIT ========== */

    function test_exit_withdrawsAndClaimsAll() public {
        _notify(address(rewardTokenA), REWARD);
        vm.prank(ALICE);
        staking.stake(STAKE);
        skip(1 days);

        uint256 expectedReward = staking.earned(ALICE, address(rewardTokenA));
        vm.prank(ALICE);
        staking.exit();

        assertEq(staking.balances(ALICE), 0);
        assertEq(staking.totalSupply(), 0);
        assertEq(stakingToken.balanceOf(ALICE), 1_000_000e18);
        assertEq(rewardTokenA.balanceOf(ALICE), expectedReward);
    }

    function test_exit_multipleRewardTokens() public {
        _addTokenB();
        _notify(address(rewardTokenA), REWARD);
        _notify(address(rewardTokenB), REWARD);

        vm.prank(ALICE);
        staking.stake(STAKE);
        skip(DURATION);

        vm.prank(ALICE);
        staking.exit();

        assertApproxEqAbs(rewardTokenA.balanceOf(ALICE), REWARD, DURATION);
        assertApproxEqAbs(rewardTokenB.balanceOf(ALICE), REWARD, DURATION);
    }

    /* ========== NOTIFY REWARD AMOUNT ========== */

    function test_notifyRewardAmount_newPeriod() public {
        _notify(address(rewardTokenA), REWARD);

        assertEq(staking.lastUpdateTime(address(rewardTokenA)), block.timestamp);
        assertEq(staking.periodFinish(address(rewardTokenA)), block.timestamp + DURATION);
        assertEq(staking.rewardRate(address(rewardTokenA)), REWARD * WAD / DURATION);
    }

    function test_notifyRewardAmount_emitsEvent() public {
        rewardTokenA.mint(address(staking), REWARD);
        vm.prank(DISTRIBUTOR);
        vm.expectEmit(true, false, false, true);
        emit StakingMultiRewards.RewardAdded(address(rewardTokenA), REWARD);
        staking.notifyRewardAmount(address(rewardTokenA), REWARD);
    }

    function test_notifyRewardAmount_midPeriodTopUp() public {
        _notify(address(rewardTokenA), REWARD);
        uint256 rateFirst = staking.rewardRate(address(rewardTokenA));

        skip(3 days);
        _notify(address(rewardTokenA), REWARD);

        uint256 remaining = DURATION - 3 days;
        uint256 leftOver = rateFirst * remaining / WAD;
        uint256 expectedRate = (REWARD + leftOver) * WAD / DURATION;

        assertEq(staking.rewardRate(address(rewardTokenA)), expectedRate);
        assertEq(staking.periodFinish(address(rewardTokenA)), block.timestamp + DURATION);
    }

    function test_notifyRewardAmount_afterPeriodEnds() public {
        _notify(address(rewardTokenA), REWARD);
        skip(DURATION + 1);

        _notify(address(rewardTokenA), REWARD);
        assertEq(staking.rewardRate(address(rewardTokenA)), REWARD * WAD / DURATION);
    }

    function test_notifyRewardAmount_revertsIfNotAdded() public {
        rewardTokenB.mint(address(staking), REWARD);
        vm.prank(DISTRIBUTOR);
        vm.expectRevert("rewardToken not added");
        staking.notifyRewardAmount(address(rewardTokenB), REWARD);
    }

    function test_notifyRewardAmount_revertsIfNotDistributor() public {
        rewardTokenA.mint(address(staking), REWARD);
        vm.prank(ALICE);
        vm.expectRevert("Caller is not RewardsDistribution contract");
        staking.notifyRewardAmount(address(rewardTokenA), REWARD);
    }

    function test_notifyRewardAmount_revertsIfRewardTooHigh() public {
        rewardTokenA.mint(address(staking), REWARD / 2);
        vm.prank(DISTRIBUTOR);
        vm.expectRevert("Provided reward too high");
        staking.notifyRewardAmount(address(rewardTokenA), REWARD);
    }

    /* ========== RECOVER ERC20 ========== */

    function test_recoverERC20_success() public {
        randomToken.mint(address(staking), 1000e18);
        vm.prank(OWNER);
        staking.recoverERC20(address(randomToken), 1000e18);

        assertEq(randomToken.balanceOf(OWNER), 1000e18);
        assertEq(randomToken.balanceOf(address(staking)), 0);
    }

    function test_recoverERC20_emitsEvent() public {
        randomToken.mint(address(staking), 1000e18);
        vm.prank(OWNER);
        vm.expectEmit(false, false, false, true);
        emit StakingMultiRewards.Recovered(address(randomToken), 1000e18);
        staking.recoverERC20(address(randomToken), 1000e18);
    }

    function test_recoverERC20_revertsForStakingToken() public {
        vm.prank(OWNER);
        vm.expectRevert("Cannot withdraw the staking token");
        staking.recoverERC20(address(stakingToken), 1);
    }

    function test_recoverERC20_revertsForRewardToken() public {
        vm.prank(OWNER);
        vm.expectRevert("Cannot withdraw a reward token");
        staking.recoverERC20(address(rewardTokenA), 1);
    }

    function test_recoverERC20_revertsIfNotOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        staking.recoverERC20(address(randomToken), 1);
    }

    /* ========== SET REWARDS DURATION ========== */

    function test_setRewardsDuration_afterPeriodEnds() public {
        _notify(address(rewardTokenA), REWARD);
        skip(DURATION + 1);

        vm.prank(OWNER);
        staking.setRewardsDuration(address(rewardTokenA), 14 days);
        assertEq(staking.rewardsDuration(address(rewardTokenA)), 14 days);
    }

    function test_setRewardsDuration_beforeFirstNotify() public {
        vm.prank(OWNER);
        staking.setRewardsDuration(address(rewardTokenA), 30 days);
        assertEq(staking.rewardsDuration(address(rewardTokenA)), 30 days);
    }

    function test_setRewardsDuration_emitsEvent() public {
        vm.prank(OWNER);
        vm.expectEmit(true, false, false, true);
        emit StakingMultiRewards.RewardsDurationUpdated(address(rewardTokenA), 14 days);
        staking.setRewardsDuration(address(rewardTokenA), 14 days);
    }

    function test_setRewardsDuration_revertsIfNotAdded() public {
        vm.prank(OWNER);
        vm.expectRevert("rewardToken not added");
        staking.setRewardsDuration(address(rewardTokenB), DURATION);
    }

    function test_setRewardsDuration_revertsIfStillStreaming() public {
        _notify(address(rewardTokenA), REWARD);
        vm.prank(OWNER);
        vm.expectRevert("rewards are still streaming");
        staking.setRewardsDuration(address(rewardTokenA), 14 days);
    }

    function test_setRewardsDuration_revertsIfZero() public {
        vm.prank(OWNER);
        vm.expectRevert("stream rewards atleast a second");
        staking.setRewardsDuration(address(rewardTokenA), 0);
    }

    function test_setRewardsDuration_revertsIfNotOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        staking.setRewardsDuration(address(rewardTokenA), DURATION);
    }

    /* ========== SET REWARDS DISTRIBUTION ========== */

    function test_setRewardsDistribution_success() public {
        vm.prank(OWNER);
        staking.setRewardsDistribution(ALICE);
        assertEq(staking.rewardsDistribution(), ALICE);
    }

    function test_setRewardsDistribution_revertsIfNotOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        staking.setRewardsDistribution(ALICE);
    }

    /* ========== PAUSE / UNPAUSE ========== */

    function test_pause_blocksStaking() public {
        vm.prank(OWNER);
        staking.pause();
        vm.prank(ALICE);
        vm.expectRevert();
        staking.stake(STAKE);
    }

    function test_unPause_allowsStaking() public {
        vm.prank(OWNER);
        staking.pause();
        vm.prank(OWNER);
        staking.unPause();

        vm.prank(ALICE);
        staking.stake(STAKE);
        assertEq(staking.balances(ALICE), STAKE);
    }

    function test_pause_revertsIfNotOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        staking.pause();
    }

    function test_unPause_revertsIfNotOwner() public {
        vm.prank(OWNER);
        staking.pause();
        vm.prank(ALICE);
        vm.expectRevert();
        staking.unPause();
    }

    /* ===================================================================
       MATH — exact values using clean numbers (604800e18 / 7 days = 1e18/s)
       =================================================================== */

    function test_math_singleStakerFullPeriod_exact() public {
        _notify(address(rewardTokenA), REWARD);

        vm.prank(ALICE);
        staking.stake(100e18);
        skip(DURATION);

        vm.prank(ALICE);
        staking.exit();

        assertEq(rewardTokenA.balanceOf(ALICE), REWARD);
        assertEq(rewardTokenA.balanceOf(address(staking)), 0);
    }

    function test_math_twoStakers_exactValues() public {
        _notify(address(rewardTokenA), REWARD);

        vm.prank(ALICE);
        staking.stake(100e18);
        skip(1 days);

        assertEq(staking.rewardPerToken(address(rewardTokenA)), 864e18);
        assertEq(staking.earned(ALICE, address(rewardTokenA)), 86_400e18);

        vm.prank(BOB);
        staking.stake(50e18);
        skip(2 days);

        assertEq(staking.rewardPerToken(address(rewardTokenA)), 2016e18);
        assertEq(staking.earned(ALICE, address(rewardTokenA)), 201_600e18);
        assertEq(staking.earned(BOB, address(rewardTokenA)), 57_600e18);

        vm.prank(ALICE);
        staking.getReward(address(rewardTokenA));
        assertEq(rewardTokenA.balanceOf(ALICE), 201_600e18);
        assertEq(staking.earned(ALICE, address(rewardTokenA)), 0);

        skip(4 days);

        assertEq(staking.rewardPerToken(address(rewardTokenA)), 4320e18);

        vm.prank(BOB);
        staking.exit();
        assertEq(rewardTokenA.balanceOf(BOB), 172_800e18);

        vm.prank(ALICE);
        staking.exit();
        assertEq(rewardTokenA.balanceOf(ALICE), 432_000e18);

        assertEq(
            rewardTokenA.balanceOf(ALICE) + rewardTokenA.balanceOf(BOB),
            REWARD
        );
        assertEq(rewardTokenA.balanceOf(address(staking)), 0);
    }

    function test_math_threeStakers_proportionalSplit() public {
        _notify(address(rewardTokenA), REWARD);

        vm.prank(ALICE);
        staking.stake(50e18);
        vm.prank(BOB);
        staking.stake(30e18);
        vm.prank(CAROL);
        staking.stake(20e18);

        skip(DURATION);

        vm.prank(ALICE);
        staking.exit();
        vm.prank(BOB);
        staking.exit();
        vm.prank(CAROL);
        staking.exit();

        uint256 aliceR = rewardTokenA.balanceOf(ALICE);
        uint256 bobR = rewardTokenA.balanceOf(BOB);
        uint256 carolR = rewardTokenA.balanceOf(CAROL);

        assertApproxEqAbs(aliceR, REWARD * 50 / 100, 1);
        assertApproxEqAbs(bobR, REWARD * 30 / 100, 1);
        assertApproxEqAbs(carolR, REWARD * 20 / 100, 1);
        assertEq(aliceR + bobR + carolR, REWARD);
    }

    function test_math_multipleRewardTokens_independentAccounting() public {
        _addTokenB();
        _notify(address(rewardTokenA), REWARD);
        _notify(address(rewardTokenB), REWARD * 2);

        vm.prank(ALICE);
        staking.stake(STAKE);
        skip(DURATION);

        vm.prank(ALICE);
        staking.getAllRewards();

        assertApproxEqAbs(rewardTokenA.balanceOf(ALICE), REWARD, 1);
        assertApproxEqAbs(rewardTokenB.balanceOf(ALICE), REWARD * 2, 1);
    }

    /* ========== MATH — WAD SCALING PRECISION ========== */

    function test_math_wadScaling_preventsZeroRate() public {
        uint256 smallReward = 100;
        rewardTokenA.mint(address(staking), smallReward);
        vm.prank(DISTRIBUTOR);
        staking.notifyRewardAmount(address(rewardTokenA), smallReward);

        assertTrue(staking.rewardRate(address(rewardTokenA)) > 0);
    }

    function test_math_wadScaling_smallRewardRecovery() public {
        uint256 smallReward = 1e18;
        rewardTokenA.mint(address(staking), smallReward);
        vm.prank(DISTRIBUTOR);
        staking.notifyRewardAmount(address(rewardTokenA), smallReward);

        vm.prank(ALICE);
        staking.stake(1e18);
        skip(DURATION);

        vm.prank(ALICE);
        staking.getReward(address(rewardTokenA));

        assertApproxEqAbs(rewardTokenA.balanceOf(ALICE), smallReward, DURATION);
    }

    function test_math_getRewardForDuration_accuracy() public {
        uint256 oddReward = 1_000_000e18;
        rewardTokenA.mint(address(staking), oddReward);
        vm.prank(DISTRIBUTOR);
        staking.notifyRewardAmount(address(rewardTokenA), oddReward);

        uint256 reported = staking.getRewardForDuration(address(rewardTokenA));
        assertApproxEqAbs(reported, oddReward, 1);
    }

    /* ========== EDGE CASES ========== */

    function test_edge_stakeBeforeNotify_earnsFromNotifyOnward() public {
        vm.prank(ALICE);
        staking.stake(STAKE);
        skip(1 days);

        assertEq(staking.earned(ALICE, address(rewardTokenA)), 0);

        _notify(address(rewardTokenA), REWARD);
        skip(DURATION);

        vm.prank(ALICE);
        staking.exit();
        assertEq(rewardTokenA.balanceOf(ALICE), REWARD);
    }

    function test_edge_claimTwice_secondClaimGetsZero() public {
        _notify(address(rewardTokenA), REWARD);
        vm.prank(ALICE);
        staking.stake(STAKE);
        skip(1 days);

        vm.prank(ALICE);
        staking.getReward(address(rewardTokenA));
        uint256 first = rewardTokenA.balanceOf(ALICE);
        assertTrue(first > 0);

        vm.prank(ALICE);
        staking.getReward(address(rewardTokenA));
        assertEq(rewardTokenA.balanceOf(ALICE), first);
    }

    function test_edge_noStakers_rewardsLost() public {
        _notify(address(rewardTokenA), REWARD);
        skip(3 days);

        assertEq(staking.rewardPerToken(address(rewardTokenA)), 0);

        vm.prank(ALICE);
        staking.stake(STAKE);
        skip(4 days);

        vm.prank(ALICE);
        staking.exit();

        uint256 got = rewardTokenA.balanceOf(ALICE);
        uint256 expected = REWARD * 4 / 7;
        assertApproxEqAbs(got, expected, 1);
    }

    function test_edge_stakeWithdrawRestake_rewardsPreserved() public {
        _notify(address(rewardTokenA), REWARD);

        vm.prank(ALICE);
        staking.stake(STAKE);
        skip(1 days);

        vm.prank(ALICE);
        staking.withdraw(STAKE);

        uint256 checkpointed = staking.rewards(ALICE, address(rewardTokenA));
        assertEq(checkpointed, 86_400e18);

        skip(1 days);

        vm.prank(ALICE);
        staking.stake(STAKE);
        skip(1 days);

        uint256 totalEarned = staking.earned(ALICE, address(rewardTokenA));
        assertEq(totalEarned, 86_400e18 * 2);
    }

    function test_edge_midPeriodTopUp_totalDistributed() public {
        _notify(address(rewardTokenA), REWARD);
        vm.prank(ALICE);
        staking.stake(STAKE);

        skip(3 days);
        _notify(address(rewardTokenA), REWARD);
        skip(DURATION);

        vm.prank(ALICE);
        staking.exit();

        uint256 got = rewardTokenA.balanceOf(ALICE);
        assertApproxEqAbs(got, REWARD * 2, DURATION * 2);
    }

    function test_edge_exitWithNoRewardTokens() public {
        StakingMultiRewards bare = new StakingMultiRewards(
            OWNER, IERC20(address(stakingToken)), DISTRIBUTOR
        );

        vm.prank(ALICE);
        stakingToken.approve(address(bare), type(uint256).max);
        vm.prank(ALICE);
        bare.stake(STAKE);

        vm.prank(ALICE);
        bare.exit();

        assertEq(bare.balances(ALICE), 0);
        assertEq(bare.totalSupply(), 0);
    }

    /* ========== INVARIANT: DISTRIBUTED <= NOTIFIED ========== */

    function test_invariant_distributedNeverExceedsNotified() public {
        _addTokenB();
        _notify(address(rewardTokenA), REWARD);
        _notify(address(rewardTokenB), REWARD * 3);

        vm.prank(ALICE);
        staking.stake(100e18);
        vm.prank(BOB);
        staking.stake(50e18);

        skip(2 days);
        vm.prank(ALICE);
        staking.getReward(address(rewardTokenA));

        skip(3 days);
        vm.prank(BOB);
        staking.getAllRewards();

        skip(DURATION);
        vm.prank(ALICE);
        staking.exit();
        vm.prank(BOB);
        staking.exit();

        uint256 totalA = rewardTokenA.balanceOf(ALICE) + rewardTokenA.balanceOf(BOB);
        uint256 totalB = rewardTokenB.balanceOf(ALICE) + rewardTokenB.balanceOf(BOB);

        assertLe(totalA, REWARD);
        assertLe(totalB, REWARD * 3);
        assertApproxEqAbs(totalA, REWARD, DURATION);
        assertApproxEqAbs(totalB, REWARD * 3, DURATION);
    }

    function test_invariant_totalSupplyMatchesSumOfBalances() public {
        vm.prank(ALICE);
        staking.stake(100e18);
        vm.prank(BOB);
        staking.stake(50e18);
        vm.prank(CAROL);
        staking.stake(25e18);

        assertEq(staking.totalSupply(), staking.balances(ALICE) + staking.balances(BOB) + staking.balances(CAROL));

        vm.prank(BOB);
        staking.withdraw(20e18);

        assertEq(staking.totalSupply(), staking.balances(ALICE) + staking.balances(BOB) + staking.balances(CAROL));
    }

    /* ===================================================================
       GAS SCALING — measure cost of updateRewards with 1..20 reward tokens
       =================================================================== */

    function _deployFreshWithNTokens(uint256 n) internal returns (StakingMultiRewards s, ERC20Mock[] memory tokens) {
        ERC20Mock stkn = new ERC20Mock();
        s = new StakingMultiRewards(OWNER, IERC20(address(stkn)), DISTRIBUTOR);

        tokens = new ERC20Mock[](n);
        for (uint256 i = 0; i < n; i++) {
            tokens[i] = new ERC20Mock();
            vm.prank(OWNER);
            s.addRewardToken(address(tokens[i]), DURATION);
            tokens[i].mint(address(s), REWARD);
            vm.prank(DISTRIBUTOR);
            s.notifyRewardAmount(address(tokens[i]), REWARD);
        }

        stkn.mint(ALICE, 1_000_000e18);
        vm.prank(ALICE);
        stkn.approve(address(s), type(uint256).max);
        stkn.mint(BOB, 1_000_000e18);
        vm.prank(BOB);
        stkn.approve(address(s), type(uint256).max);
    }

    function test_gasScaling_20tokens_stake() public {
        (StakingMultiRewards s,) = _deployFreshWithNTokens(20);

        vm.prank(ALICE);
        uint256 g0 = gasleft();
        s.stake(STAKE);
        uint256 g1 = gasleft();
        emit log_named_uint("gas_stake_20tokens", g0 - g1);

        assertEq(s.balances(ALICE), STAKE);
    }

    function test_gasScaling_20tokens_withdraw() public {
        (StakingMultiRewards s,) = _deployFreshWithNTokens(20);
        vm.prank(ALICE);
        s.stake(STAKE);
        skip(1 days);

        vm.prank(ALICE);
        uint256 g0 = gasleft();
        s.withdraw(STAKE);
        uint256 g1 = gasleft();
        emit log_named_uint("gas_withdraw_20tokens", g0 - g1);

        assertEq(s.balances(ALICE), 0);
    }

    function test_gasScaling_20tokens_getAllRewards() public {
        (StakingMultiRewards s, ERC20Mock[] memory tokens) = _deployFreshWithNTokens(20);
        vm.prank(ALICE);
        s.stake(STAKE);
        skip(1 days);

        vm.prank(ALICE);
        uint256 g0 = gasleft();
        s.getAllRewards();
        uint256 g1 = gasleft();
        emit log_named_uint("gas_getAllRewards_20tokens", g0 - g1);

        for (uint256 i = 0; i < 20; i++) {
            assertTrue(tokens[i].balanceOf(ALICE) > 0);
        }
    }

    function test_gasScaling_20tokens_exit() public {
        (StakingMultiRewards s,) = _deployFreshWithNTokens(20);
        vm.prank(ALICE);
        s.stake(STAKE);
        skip(1 days);

        vm.prank(ALICE);
        uint256 g0 = gasleft();
        s.exit();
        uint256 g1 = gasleft();
        emit log_named_uint("gas_exit_20tokens", g0 - g1);

        assertEq(s.balances(ALICE), 0);
    }

    function test_gasScaling_20tokens_notifyRewardAmount() public {
        (StakingMultiRewards s, ERC20Mock[] memory tokens) = _deployFreshWithNTokens(20);
        vm.prank(ALICE);
        s.stake(STAKE);
        skip(1 days);

        tokens[0].mint(address(s), REWARD);
        vm.prank(DISTRIBUTOR);
        uint256 g0 = gasleft();
        s.notifyRewardAmount(address(tokens[0]), REWARD);
        uint256 g1 = gasleft();
        emit log_named_uint("gas_notify_20tokens", g0 - g1);
    }

    function test_gasScaling_perTokenCost() public {
        uint256[5] memory counts = [uint256(1), 5, 10, 15, 20];
        uint256[5] memory stakeGas;
        uint256[5] memory withdrawGas;
        uint256[5] memory claimGas;
        uint256[5] memory notifyGas;

        for (uint256 c = 0; c < counts.length; c++) {
            (StakingMultiRewards s, ERC20Mock[] memory tokens) = _deployFreshWithNTokens(counts[c]);

            vm.prank(ALICE);
            uint256 g0 = gasleft();
            s.stake(STAKE);
            stakeGas[c] = g0 - gasleft();

            skip(1 days);

            vm.prank(ALICE);
            g0 = gasleft();
            s.withdraw(STAKE / 2);
            withdrawGas[c] = g0 - gasleft();

            vm.prank(ALICE);
            g0 = gasleft();
            s.getAllRewards();
            claimGas[c] = g0 - gasleft();

            tokens[0].mint(address(s), REWARD);
            vm.prank(DISTRIBUTOR);
            g0 = gasleft();
            s.notifyRewardAmount(address(tokens[0]), REWARD);
            notifyGas[c] = g0 - gasleft();
        }

        emit log("=== Gas per reward token count ===");
        emit log("tokens | stake    | withdraw | claim    | notify");
        for (uint256 c = 0; c < counts.length; c++) {
            emit log_named_uint(string.concat("tokens_", vm.toString(counts[c]), "_stake"), stakeGas[c]);
            emit log_named_uint(string.concat("tokens_", vm.toString(counts[c]), "_withdraw"), withdrawGas[c]);
            emit log_named_uint(string.concat("tokens_", vm.toString(counts[c]), "_claim"), claimGas[c]);
            emit log_named_uint(string.concat("tokens_", vm.toString(counts[c]), "_notify"), notifyGas[c]);
        }

        uint256 stakePerToken = (stakeGas[4] - stakeGas[0]) / (counts[4] - counts[0]);
        uint256 withdrawPerToken = (withdrawGas[4] - withdrawGas[0]) / (counts[4] - counts[0]);
        uint256 claimPerToken = (claimGas[4] - claimGas[0]) / (counts[4] - counts[0]);
        uint256 notifyPerToken = (notifyGas[4] - notifyGas[0]) / (counts[4] - counts[0]);

        emit log("=== Marginal gas per additional reward token ===");
        emit log_named_uint("stake_per_token", stakePerToken);
        emit log_named_uint("withdraw_per_token", withdrawPerToken);
        emit log_named_uint("claim_per_token", claimPerToken);
        emit log_named_uint("notify_per_token", notifyPerToken);
    }

    function test_gasScaling_20tokens_fullFlow() public {
        (StakingMultiRewards s, ERC20Mock[] memory tokens) = _deployFreshWithNTokens(20);

        vm.prank(ALICE);
        s.stake(STAKE);

        vm.prank(BOB);
        s.stake(STAKE / 2);

        skip(3 days);

        vm.prank(ALICE);
        s.getAllRewards();

        skip(4 days);

        vm.prank(ALICE);
        s.exit();

        vm.prank(BOB);
        s.exit();

        for (uint256 i = 0; i < 20; i++) {
            uint256 aliceBal = tokens[i].balanceOf(ALICE);
            uint256 bobBal = tokens[i].balanceOf(BOB);
            assertTrue(aliceBal > 0);
            assertTrue(bobBal > 0);
            assertLe(aliceBal + bobBal, REWARD);
            assertApproxEqAbs(aliceBal + bobBal, REWARD, DURATION);
        }
    }
}
