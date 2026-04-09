// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {StakingRewards as YulStakingRewards} from "../src/StakingRewards.yul.sol";

interface IStakingRewardsLike {
    function balanceOf(address account) external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function exit() external;
    function getReward() external;
    function getRewardForDuration() external view returns (uint256);
    function lastTimeRewardApplicable() external view returns (uint256);
    function lastUpdateTime() external view returns (uint256);
    function notifyRewardAmount(uint256 reward) external;
    function periodFinish() external view returns (uint256);
    function rewardPerToken() external view returns (uint256);
    function rewardRate() external view returns (uint256);
    function rewardsDistribution() external view returns (address);
    function rewardsDuration() external view returns (uint256);
    function rewardsToken() external view returns (address);
    function stake(uint256 amount) external;
    function stakingToken() external view returns (address);
    function totalSupply() external view returns (uint256);
    function withdraw(uint256 amount) external;
}

contract StakingRewardsComparisonTest is Test {
    string internal constant LEGACY_ARTIFACT = "out/StakingRewards.sol/StakingRewards.json";

    enum Implementation {
        Legacy,
        Yul
    }

    struct Fixture {
        IStakingRewardsLike stakingRewards;
        ERC20Mock rewardsToken;
        ERC20Mock stakingToken;
    }

    address internal constant OWNER = address(0xA11CE);
    address internal constant DISTRIBUTOR = address(0xD157B1B);
    address internal constant ALICE = address(0xA71CE);
    address internal constant BOB = address(0xB0B);

    uint256 internal constant INITIAL_STAKER_BALANCE = 1_000_000e18;
    uint256 internal constant REWARD_AMOUNT = 7 days * 1e18;
    uint256 internal constant ALICE_STAKE = 100e18;
    uint256 internal constant BOB_STAKE = 50e18;

    uint256 internal constant ALICE_REWARD_AFTER_DAY_ONE = 86_400e18;
    uint256 internal constant ALICE_REWARD_AFTER_DAY_THREE = 201_600e18;
    uint256 internal constant BOB_REWARD_AFTER_DAY_THREE = 57_600e18;
    uint256 internal constant ALICE_FINAL_REWARD = 432_000e18;
    uint256 internal constant BOB_FINAL_REWARD = 172_800e18;

    function test_BothImplementationsMatchExpectedRewardsFlow() public {
        Fixture memory legacy = _deployFixture(Implementation.Legacy);
        Fixture memory yul = _deployFixture(Implementation.Yul);

        _assertMatchingState(legacy, yul);
        assertEq(legacy.stakingRewards.rewardsDistribution(), DISTRIBUTOR);
        assertEq(yul.stakingRewards.rewardsDistribution(), DISTRIBUTOR);
        assertEq(legacy.stakingRewards.rewardsToken(), address(legacy.rewardsToken));
        assertEq(yul.stakingRewards.rewardsToken(), address(yul.rewardsToken));
        assertEq(legacy.stakingRewards.stakingToken(), address(legacy.stakingToken));
        assertEq(yul.stakingRewards.stakingToken(), address(yul.stakingToken));

        _notifyRewardAmount(legacy);
        _notifyRewardAmount(yul);

        _assertMatchingState(legacy, yul);
        assertEq(legacy.stakingRewards.rewardRate(), 1e18);
        assertEq(yul.stakingRewards.rewardRate(), 1e18);
        assertEq(legacy.stakingRewards.getRewardForDuration(), REWARD_AMOUNT);
        assertEq(yul.stakingRewards.getRewardForDuration(), REWARD_AMOUNT);
        assertEq(legacy.stakingRewards.periodFinish(), block.timestamp + 7 days);
        assertEq(yul.stakingRewards.periodFinish(), block.timestamp + 7 days);

        vm.prank(ALICE);
        legacy.stakingRewards.stake(ALICE_STAKE);
        vm.prank(ALICE);
        yul.stakingRewards.stake(ALICE_STAKE);

        _assertMatchingState(legacy, yul);
        assertEq(legacy.stakingRewards.totalSupply(), ALICE_STAKE);
        assertEq(yul.stakingRewards.totalSupply(), ALICE_STAKE);

        skip(1 days);

        _assertMatchingState(legacy, yul);
        assertEq(legacy.stakingRewards.lastTimeRewardApplicable(), block.timestamp);
        assertEq(yul.stakingRewards.lastTimeRewardApplicable(), block.timestamp);
        assertEq(legacy.stakingRewards.earned(ALICE), ALICE_REWARD_AFTER_DAY_ONE);
        assertEq(yul.stakingRewards.earned(ALICE), ALICE_REWARD_AFTER_DAY_ONE);

        vm.prank(BOB);
        legacy.stakingRewards.stake(BOB_STAKE);
        vm.prank(BOB);
        yul.stakingRewards.stake(BOB_STAKE);

        _assertMatchingState(legacy, yul);
        assertEq(legacy.stakingRewards.totalSupply(), ALICE_STAKE + BOB_STAKE);
        assertEq(yul.stakingRewards.totalSupply(), ALICE_STAKE + BOB_STAKE);

        skip(2 days);

        _assertMatchingState(legacy, yul);
        assertEq(legacy.stakingRewards.earned(ALICE), ALICE_REWARD_AFTER_DAY_THREE);
        assertEq(yul.stakingRewards.earned(ALICE), ALICE_REWARD_AFTER_DAY_THREE);
        assertEq(legacy.stakingRewards.earned(BOB), BOB_REWARD_AFTER_DAY_THREE);
        assertEq(yul.stakingRewards.earned(BOB), BOB_REWARD_AFTER_DAY_THREE);

        vm.prank(ALICE);
        legacy.stakingRewards.getReward();
        vm.prank(ALICE);
        yul.stakingRewards.getReward();

        _assertMatchingState(legacy, yul);
        assertEq(legacy.rewardsToken.balanceOf(ALICE), ALICE_REWARD_AFTER_DAY_THREE);
        assertEq(yul.rewardsToken.balanceOf(ALICE), ALICE_REWARD_AFTER_DAY_THREE);
        assertEq(legacy.stakingRewards.earned(ALICE), 0);
        assertEq(yul.stakingRewards.earned(ALICE), 0);

        skip(4 days);

        _assertMatchingState(legacy, yul);
        assertEq(legacy.stakingRewards.lastTimeRewardApplicable(), legacy.stakingRewards.periodFinish());
        assertEq(yul.stakingRewards.lastTimeRewardApplicable(), yul.stakingRewards.periodFinish());

        vm.prank(BOB);
        legacy.stakingRewards.exit();
        vm.prank(BOB);
        yul.stakingRewards.exit();

        _assertMatchingState(legacy, yul);
        assertEq(legacy.rewardsToken.balanceOf(BOB), BOB_FINAL_REWARD);
        assertEq(yul.rewardsToken.balanceOf(BOB), BOB_FINAL_REWARD);
        assertEq(legacy.stakingToken.balanceOf(BOB), INITIAL_STAKER_BALANCE);
        assertEq(yul.stakingToken.balanceOf(BOB), INITIAL_STAKER_BALANCE);

        vm.prank(ALICE);
        legacy.stakingRewards.exit();
        vm.prank(ALICE);
        yul.stakingRewards.exit();

        _assertMatchingState(legacy, yul);
        assertEq(legacy.stakingRewards.totalSupply(), 0);
        assertEq(yul.stakingRewards.totalSupply(), 0);
        assertEq(legacy.rewardsToken.balanceOf(ALICE), ALICE_FINAL_REWARD);
        assertEq(yul.rewardsToken.balanceOf(ALICE), ALICE_FINAL_REWARD);
        assertEq(legacy.rewardsToken.balanceOf(address(legacy.stakingRewards)), 0);
        assertEq(yul.rewardsToken.balanceOf(address(yul.stakingRewards)), 0);
        assertEq(legacy.stakingToken.balanceOf(ALICE), INITIAL_STAKER_BALANCE);
        assertEq(yul.stakingToken.balanceOf(ALICE), INITIAL_STAKER_BALANCE);
    }

    function testGas_Deploy_Legacy() public {
        _measureDeployGas(Implementation.Legacy);
    }

    function testGas_Deploy_Yul() public {
        _measureDeployGas(Implementation.Yul);
    }

    function testGas_NotifyRewardAmount_Legacy() public {
        _measureNotifyRewardAmountGas(Implementation.Legacy);
    }

    function testGas_NotifyRewardAmount_Yul() public {
        _measureNotifyRewardAmountGas(Implementation.Yul);
    }

    function testGas_Stake_Legacy() public {
        _measureStakeGas(Implementation.Legacy);
    }

    function testGas_Stake_Yul() public {
        _measureStakeGas(Implementation.Yul);
    }

    function testGas_Withdraw_Legacy() public {
        _measureWithdrawGas(Implementation.Legacy);
    }

    function testGas_Withdraw_Yul() public {
        _measureWithdrawGas(Implementation.Yul);
    }

    function testGas_GetReward_Legacy() public {
        _measureGetRewardGas(Implementation.Legacy);
    }

    function testGas_GetReward_Yul() public {
        _measureGetRewardGas(Implementation.Yul);
    }

    function testGas_Exit_Legacy() public {
        _measureExitGas(Implementation.Legacy);
    }

    function testGas_Exit_Yul() public {
        _measureExitGas(Implementation.Yul);
    }

    function _measureDeployGas(Implementation implementation) internal {
        vm.pauseGasMetering();
        ERC20Mock rewardsToken = new ERC20Mock();
        ERC20Mock stakingToken = new ERC20Mock();
        bytes memory legacyBytecode = vm.getCode(LEGACY_ARTIFACT);
        bytes memory legacyArgs = abi.encode(OWNER, DISTRIBUTOR, address(rewardsToken), address(stakingToken));
        vm.resumeGasMetering();

        IStakingRewardsLike stakingRewards;
        if (implementation == Implementation.Legacy) {
            bytes memory initCode = abi.encodePacked(legacyBytecode, legacyArgs);
            address deployed;
            assembly ("memory-safe") {
                deployed := create(0, add(initCode, 0x20), mload(initCode))
            }
            require(deployed != address(0), "legacy deployment failed");
            stakingRewards = IStakingRewardsLike(deployed);
        } else {
            stakingRewards = _deployStakingRewards(implementation, rewardsToken, stakingToken);
        }

        vm.pauseGasMetering();
        assertEq(stakingRewards.rewardsDistribution(), DISTRIBUTOR);
        assertEq(stakingRewards.rewardsToken(), address(rewardsToken));
        assertEq(stakingRewards.stakingToken(), address(stakingToken));
    }

    function _measureNotifyRewardAmountGas(Implementation implementation) internal {
        vm.pauseGasMetering();
        Fixture memory fixture = _deployFixture(implementation);
        fixture.rewardsToken.mint(address(fixture.stakingRewards), REWARD_AMOUNT);
        vm.resumeGasMetering();

        vm.prank(DISTRIBUTOR);
        fixture.stakingRewards.notifyRewardAmount(REWARD_AMOUNT);

        vm.pauseGasMetering();
        assertEq(fixture.stakingRewards.rewardRate(), 1e18);
        assertEq(fixture.stakingRewards.periodFinish(), block.timestamp + 7 days);
    }

    function _measureStakeGas(Implementation implementation) internal {
        vm.pauseGasMetering();
        Fixture memory fixture = _deployFixture(implementation);
        _notifyRewardAmount(fixture);
        vm.resumeGasMetering();

        vm.prank(ALICE);
        fixture.stakingRewards.stake(ALICE_STAKE);

        vm.pauseGasMetering();
        assertEq(fixture.stakingRewards.balanceOf(ALICE), ALICE_STAKE);
        assertEq(fixture.stakingRewards.totalSupply(), ALICE_STAKE);
    }

    function _measureWithdrawGas(Implementation implementation) internal {
        vm.pauseGasMetering();
        Fixture memory fixture = _deployFixture(implementation);
        _notifyRewardAmount(fixture);
        vm.prank(ALICE);
        fixture.stakingRewards.stake(ALICE_STAKE);
        skip(1 days);
        vm.resumeGasMetering();

        vm.prank(ALICE);
        fixture.stakingRewards.withdraw(ALICE_STAKE / 2);

        vm.pauseGasMetering();
        assertEq(fixture.stakingRewards.balanceOf(ALICE), ALICE_STAKE / 2);
        assertEq(fixture.stakingRewards.totalSupply(), ALICE_STAKE / 2);
    }

    function _measureGetRewardGas(Implementation implementation) internal {
        vm.pauseGasMetering();
        Fixture memory fixture = _deployFixture(implementation);
        _notifyRewardAmount(fixture);
        vm.prank(ALICE);
        fixture.stakingRewards.stake(ALICE_STAKE);
        skip(1 days);
        vm.resumeGasMetering();

        vm.prank(ALICE);
        fixture.stakingRewards.getReward();

        vm.pauseGasMetering();
        assertEq(fixture.rewardsToken.balanceOf(ALICE), ALICE_REWARD_AFTER_DAY_ONE);
        assertEq(fixture.stakingRewards.earned(ALICE), 0);
    }

    function _measureExitGas(Implementation implementation) internal {
        vm.pauseGasMetering();
        Fixture memory fixture = _deployFixture(implementation);
        _notifyRewardAmount(fixture);
        vm.prank(ALICE);
        fixture.stakingRewards.stake(ALICE_STAKE);
        skip(1 days);
        vm.resumeGasMetering();

        vm.prank(ALICE);
        fixture.stakingRewards.exit();

        vm.pauseGasMetering();
        assertEq(fixture.stakingRewards.totalSupply(), 0);
        assertEq(fixture.stakingRewards.balanceOf(ALICE), 0);
        assertEq(fixture.stakingToken.balanceOf(ALICE), INITIAL_STAKER_BALANCE);
        assertEq(fixture.rewardsToken.balanceOf(ALICE), ALICE_REWARD_AFTER_DAY_ONE);
    }

    function _deployFixture(Implementation implementation) internal returns (Fixture memory fixture) {
        fixture.rewardsToken = new ERC20Mock();
        fixture.stakingToken = new ERC20Mock();
        fixture.stakingRewards = _deployStakingRewards(implementation, fixture.rewardsToken, fixture.stakingToken);

        fixture.stakingToken.mint(ALICE, INITIAL_STAKER_BALANCE);
        fixture.stakingToken.mint(BOB, INITIAL_STAKER_BALANCE);

        vm.prank(ALICE);
        fixture.stakingToken.approve(address(fixture.stakingRewards), type(uint256).max);
        vm.prank(BOB);
        fixture.stakingToken.approve(address(fixture.stakingRewards), type(uint256).max);
    }

    function _deployStakingRewards(Implementation implementation, ERC20Mock rewardsToken, ERC20Mock stakingToken)
        internal
        returns (IStakingRewardsLike stakingRewards)
    {
        if (implementation == Implementation.Legacy) {
            stakingRewards = IStakingRewardsLike(
                deployCode(
                    LEGACY_ARTIFACT, abi.encode(OWNER, DISTRIBUTOR, address(rewardsToken), address(stakingToken))
                )
            );
        } else {
            stakingRewards =
                IStakingRewardsLike(address(new YulStakingRewards(OWNER, rewardsToken, stakingToken, DISTRIBUTOR)));
        }
    }

    function _notifyRewardAmount(Fixture memory fixture) internal {
        fixture.rewardsToken.mint(address(fixture.stakingRewards), REWARD_AMOUNT);

        vm.prank(DISTRIBUTOR);
        fixture.stakingRewards.notifyRewardAmount(REWARD_AMOUNT);
    }

    function _assertMatchingState(Fixture memory legacy, Fixture memory yul) internal view {
        assertEq(legacy.stakingRewards.totalSupply(), yul.stakingRewards.totalSupply());
        assertEq(legacy.stakingRewards.balanceOf(ALICE), yul.stakingRewards.balanceOf(ALICE));
        assertEq(legacy.stakingRewards.balanceOf(BOB), yul.stakingRewards.balanceOf(BOB));
        assertEq(legacy.stakingRewards.earned(ALICE), yul.stakingRewards.earned(ALICE));
        assertEq(legacy.stakingRewards.earned(BOB), yul.stakingRewards.earned(BOB));
        assertEq(legacy.stakingRewards.rewardPerToken(), yul.stakingRewards.rewardPerToken());
        assertEq(legacy.stakingRewards.rewardRate(), yul.stakingRewards.rewardRate());
        assertEq(legacy.stakingRewards.rewardsDuration(), yul.stakingRewards.rewardsDuration());
        assertEq(legacy.stakingRewards.lastUpdateTime(), yul.stakingRewards.lastUpdateTime());
        assertEq(legacy.stakingRewards.periodFinish(), yul.stakingRewards.periodFinish());
        assertEq(legacy.stakingRewards.getRewardForDuration(), yul.stakingRewards.getRewardForDuration());
        assertEq(legacy.rewardsToken.balanceOf(ALICE), yul.rewardsToken.balanceOf(ALICE));
        assertEq(legacy.rewardsToken.balanceOf(BOB), yul.rewardsToken.balanceOf(BOB));
        assertEq(
            legacy.rewardsToken.balanceOf(address(legacy.stakingRewards)),
            yul.rewardsToken.balanceOf(address(yul.stakingRewards))
        );
        assertEq(legacy.stakingToken.balanceOf(ALICE), yul.stakingToken.balanceOf(ALICE));
        assertEq(legacy.stakingToken.balanceOf(BOB), yul.stakingToken.balanceOf(BOB));
        assertEq(
            legacy.stakingToken.balanceOf(address(legacy.stakingRewards)),
            yul.stakingToken.balanceOf(address(yul.stakingRewards))
        );
    }
}
