//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

/// @notice Rewriting `synthetix/contracts/StakingRewards.sol` in  0.8.0 compiler version with latest openzeppelin lib
contract StakingRewards is Ownable, Pausable, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    uint256 private constant WAD = 1e18;

    /* ========== STATE VARIABLES ========== */

    IERC20 public rewardsToken;
    IERC20 public stakingToken;

    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 7 days;
    uint256 public periodFinish = 0;
    uint256 public lastUpdateTime;

    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) public rewards;

    address public rewardsDistribution;


    /* ========== CONSTRUCTOR ========== */

    constructor(address owner, IERC20 _rewardsToken, IERC20 _stakingToken, address _rewardsDistribution) Ownable(owner) {
        assembly {
            sstore(rewardsToken.slot, _rewardsToken)
            sstore(stakingToken.slot, _stakingToken)
            sstore(rewardsDistribution.slot, _rewardsDistribution)
        }
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256 result) {
        assembly {
            result := sload(_totalSupply.slot)
        }
    }

    function balanceOf(address account) external view returns (uint256 result) {
        assembly {
            mstore(0x00, account)
            mstore(0x20, _balances.slot)
            result := sload(keccak256(0x00, 0x40))
        }
    }

    function lastTimeRewardApplicable() public view returns (uint256 result) {
        assembly {
            let periodFinish_ := sload(periodFinish.slot)
            result := timestamp()

            if gt(result, periodFinish_) {
                result := periodFinish_
            }
        }
    }

    function rewardPerToken() public view returns (uint256 result) {
        assembly {
            let totalSupply_ := sload(_totalSupply.slot)
            if iszero(totalSupply_) {
                result := sload(rewardPerTokenStored.slot)
            }

            if totalSupply_ {
                let periodFinish_ := sload(periodFinish.slot)
                let maxTimestamp := timestamp()
                if gt(maxTimestamp, periodFinish_) {
                    maxTimestamp := periodFinish_
                }
                let timePeriod := sub(maxTimestamp, sload(lastUpdateTime.slot))

                result := safeAdd(
                    sload(rewardPerTokenStored.slot),
                    div(safeMul(safeMul(timePeriod, sload(rewardRate.slot)), WAD), totalSupply_)
                )
            }

            function safeAdd(a, b) -> r {
                r := add(a, b)
                if lt(r, a) {revert(0,0)}
            }
            function safeMul(a, b) -> r {
                r := mul(a, b)
                if iszero(or(iszero(a), eq(div(r, a), b))) {revert(0,0)}
            }
        }
    }

    function earned(address account) public view returns(uint256 result) {
        uint256 rewardPerToken_ = rewardPerToken();
        assembly {
            mstore(0x00, account)
            mstore(0x20, rewards.slot)
            let rewardSlot := keccak256(0x00, 0x40)
            mstore(0x20, userRewardPerTokenPaid.slot)
            let userRewardPerTokenPaidSlot := keccak256(0x00, 0x40)
            mstore(0x20, _balances.slot)
            let balanceSlot := keccak256(0x00, 0x40)

            result := safeAdd(
                sload(rewardSlot),
                div(safeMul(safeSub(rewardPerToken_, sload(userRewardPerTokenPaidSlot)), sload(balanceSlot)), WAD)
            )

            function safeAdd(a, b) -> r {
                r := add(a, b)
                if lt(r, a) {revert(0,0)}
            }
            function safeSub(a, b) -> r {
                if lt(a, b) {revert(0,0)}
                r := sub(a, b)
            }
            function safeMul(a, b) -> r {
                r := mul(a, b)
                if iszero(or(iszero(a), eq(div(r, a), b))) {revert(0,0)}
            }
        }
    }


    function getRewardForDuration() external view returns (uint256 result) {
        assembly {
            result := safeMul(sload(rewardRate.slot), sload(rewardsDuration.slot))

            function safeMul(a, b) -> r {
                r := mul(a, b)
                if iszero(or(iszero(a), eq(div(r, a), b))) {revert(0,0)}
            }
        }
    }


    /* ========== RESTRICTED FUNCTIONS ========== */

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        assembly {
            if iszero(gt(timestamp(), sload(periodFinish.slot))) {
                mstore(0x00, shl(224, 0x08c379a0)) // Error(string)
                mstore(0x04, 0x20) // offset
                mstore(0x24, 88) // length
                mstore(0x44, "Previous rewards period must be ")
                mstore(0x64, "complete before changing the dur")
                mstore(0x84, "ation for the new period")
                revert(0x00, 0xa4)
            }

            sstore(rewardsDuration.slot, _rewardsDuration)

            mstore(0x00, _rewardsDuration)
            mstore(0x20, "RewardsDurationUpdated(uint256)")
            log1(0x00, 0x20, keccak256(0x20, 31))
        }
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        uint256 lastUpdateTime_ = lastTimeRewardApplicable();
        uint256 rewardPerToken_ = rewardPerToken();
        assembly {
            sstore(lastUpdateTime.slot, lastUpdateTime_)
            sstore(rewardPerTokenStored.slot, rewardPerToken_)
        }

        if (account != address(0)) {
            uint256 earned_ = earned(account);
            assembly {
                mstore(0x00, account)
                mstore(0x20, rewards.slot)
                sstore(keccak256(0x00, 0x40), earned_)

                mstore(0x20, userRewardPerTokenPaid.slot)
                sstore(keccak256(0x00, 0x40), rewardPerToken_)
            }
        }

        _;
    }

    modifier onlyRewardsDistribution() {
        assembly {
            // no memory pointer management needed if below block triggers, it will revert anyway
            if iszero(eq(caller(), sload(rewardsDistribution.slot))) {
                mstore(0x00, shl(224, 0x08c379a0)) // Error(string)
                mstore(0x04, 0x20) // offset
                mstore(0x24, 42) // length
                mstore(0x44, "Caller is not RewardsDistributio")
                mstore(0x64, "n contract")
                revert(0x00, 0x84)
            }
        }
        _;
    }

    function setRewardsDistribution(address _rewardsDistribution) external onlyOwner {
        assembly {
            sstore(rewardsDistribution.slot, _rewardsDistribution)
        }
    }

    


}