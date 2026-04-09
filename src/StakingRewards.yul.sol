//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Rewriting `synthetix/contracts/StakingRewards.sol` in  0.8.0 compiler version with latest openzeppelin lib
contract StakingRewards is Ownable, Pausable, ReentrancyGuard {
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
                let timePeriod := safeSub(maxTimestamp, sload(lastUpdateTime.slot))

                result := safeAdd(
                    sload(rewardPerTokenStored.slot),
                    div(safeMul(safeMul(timePeriod, sload(rewardRate.slot)), WAD), totalSupply_)
                )
            }

            function safeAdd(a, b) -> r {
                r := add(a, b)
                if lt(r, a) { panic(0x11) }
            }
            function safeSub(a, b) -> r {
                if lt(a, b) { panic(0x11) }
                r := sub(a, b)
            }
            function safeMul(a, b) -> r {
                r := mul(a, b)
                if iszero(or(iszero(a), eq(div(r, a), b))) { panic(0x11) }
            }
            function panic(code) {
                mstore(0x00, shl(224, 0x4e487b71)) // Panic(uint256)
                mstore(0x04, code)
                revert(0x00, 0x24)
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
                if lt(r, a) { panic(0x11) }
            }
            function safeSub(a, b) -> r {
                if lt(a, b) { panic(0x11) }
                r := sub(a, b)
            }
            function safeMul(a, b) -> r {
                r := mul(a, b)
                if iszero(or(iszero(a), eq(div(r, a), b))) { panic(0x11) }
            }
            function panic(code) {
                mstore(0x00, shl(224, 0x4e487b71)) // Panic(uint256)
                mstore(0x04, code)
                revert(0x00, 0x24)
            }
        }
    }


    function getRewardForDuration() external view returns (uint256 result) {
        assembly {
            result := safeMul(sload(rewardRate.slot), sload(rewardsDuration.slot))

            function safeMul(a, b) -> r {
                r := mul(a, b)
                if iszero(or(iszero(a), eq(div(r, a), b))) { panic(0x11) }
            }
            function panic(code) {
                mstore(0x00, shl(224, 0x4e487b71)) // Panic(uint256)
                mstore(0x04, code)
                revert(0x00, 0x24)
            }
        }
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount) external nonReentrant whenNotPaused updateReward(msg.sender) {
        assembly {
            if iszero(amount) {
                mstore(0x00, shl(224, 0x08c379a0)) // Error(string)
                mstore(0x04, 0x20) // offset
                mstore(0x24, 14) // length
                mstore(0x44, "Cannot stake 0")
                revert(0x00, 0x64)
            }

            let slot := _totalSupply.slot
            sstore(slot, safeAdd(sload(slot), amount))

            mstore(0x00, caller())
            mstore(0x20, _balances.slot)
            slot := keccak256(0x00, 0x40)
            sstore(slot, safeAdd(sload(slot), amount))

            function safeAdd(a, b) -> r {
                r := add(a, b)
                if lt(r, a) { panic(0x11) }
            }
            function panic(code) {
                mstore(0x00, shl(224, 0x4e487b71)) // Panic(uint256)
                mstore(0x04, code)
                revert(0x00, 0x24)
            }
        }

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        assembly {
            mstore(0x00, "Staked(address,uint256)")
            mstore(0x20, amount)
            log2(0x20, 0x20, keccak256(0x00, 23), caller())
        }

    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        assembly {
            if iszero(amount) {
                mstore(0x00, shl(224, 0x08c379a0)) // Error(string)
                mstore(0x04, 0x20) // offset
                mstore(0x24, 17) // length
                mstore(0x44, "Cannot withdraw 0")
                revert(0x00, 0x64)
            }

            let slot := _totalSupply.slot
            sstore(slot, safeSub(sload(slot), amount))

            mstore(0x00, caller())
            mstore(0x20, _balances.slot)
            slot := keccak256(0x00, 0x40)
            sstore(slot, safeSub(sload(slot), amount))

            function safeSub(a, b) -> r {
                if lt(a, b) { panic(0x11) }
                r := sub(a, b)
            }
            function panic(code) {
                mstore(0x00, shl(224, 0x4e487b71)) // Panic(uint256)
                mstore(0x04, code)
                revert(0x00, 0x24)
            }
        }

        stakingToken.safeTransfer(msg.sender, amount);

        assembly {
            mstore(0x00, "Withdrawn(address,uint256)")
            mstore(0x20, amount)
            log2(0x20, 0x20, keccak256(0x00, 26), caller())
        }
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        assembly {
            mstore(0x00, caller())
            mstore(0x20, rewards.slot)
            let slot := keccak256(0x00, 0x40)
            let reward := sload(slot)

            if reward {
                sstore(slot, 0)

                mstore(0x00, "transfer(address,uint256)")
                mstore(0x00, keccak256(0x00, 25))
                mstore(0x04, caller())
                mstore(0x24, reward)

                let rewardToken := sload(rewardsToken.slot)
                let success := call(gas(), rewardToken, 0, 0x00, 0x44, 0, 0)
                if iszero(success) {
                    returndatacopy(0x00, 0x00, returndatasize())
                    revert(0x00, returndatasize())
                }
                let returnDataSize := returndatasize()
                let doRevert := 0

                if gt(returndatasize(), 31) {
                    returndatacopy(0x00, 0x00, 0x20)
                    if iszero(eq(mload(0x00), 1)) {doRevert := 1}
                }
                if lt(returnDataSize, 32){
                    if and(iszero(returnDataSize), iszero(extcodesize(rewardToken))) {doRevert := 1}
                    if returnDataSize {doRevert := 1}
                }
                if doRevert {
                    mstore(0x00, "SafeERC20FailedOperation(address")
                    mstore(0x20, shl(248, ")"))
                    mstore(0x00, keccak256(0x00, 33))
                    mstore(0x04, rewardToken)
                    revert(0x00, 0x24)
                }

                mstore(0x00, "RewardPaid(address,uint256)")
                mstore(0x20, reward)
                log2(0x20, 0x20, keccak256(0x00, 27), caller())
            }
        }
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(uint256 reward) external onlyRewardsDistribution updateReward(address(0)) {
        assembly {
            let currentTimestamp_ := timestamp()
            let periodFinish_ := sload(periodFinish.slot)
            let rewardsDuration_ := sload(rewardsDuration.slot)

            if iszero(lt(currentTimestamp_, periodFinish_)) {
                sstore(rewardRate.slot, safeDiv(reward, rewardsDuration_))
            }

            if lt(currentTimestamp_, periodFinish_) {
                let newTotalReward_ := safeAdd(
                    safeMul(sub(periodFinish_, currentTimestamp_), sload(rewardRate.slot)), 
                    reward
                )
                sstore(rewardRate.slot, safeDiv(newTotalReward_, rewardsDuration_))
            }

            mstore(0x00, "balanceOf(address)")
            mstore(0x00, keccak256(0x00, 18))
            mstore(0x04, address())
            if iszero(staticcall(gas(), sload(rewardsToken.slot), 0x00, 0x24, 0x00, 0x20)) {revert(0, 0)}
            if lt(returndatasize(), 0x20) {revert(0,0)}

            if gt(sload(rewardRate.slot), safeDiv(mload(0x00), rewardsDuration_)) {
                mstore(0x00, shl(224, 0x08c379a0)) // Error(string)
                mstore(0x04, 0x20) // offset
                mstore(0x24, 24) // length
                mstore(0x44, "Provided reward too high")
                revert(0x00, 0x64)
            }

            sstore(lastUpdateTime.slot, currentTimestamp_)
            sstore(periodFinish.slot, safeAdd(currentTimestamp_, rewardsDuration_))

            mstore(0x00, "RewardAdded(uint256)")
            let top1 := keccak256(0x00, 20)
            mstore(0x00, reward)
            log1(0x00, 0x20, top1)


            function safeAdd(a, b) -> r {
                r := add(a, b)
                if lt(r, a) { panic(0x11) }
            }
            function safeMul(a, b) -> r {
                r := mul(a, b)
                if iszero(or(iszero(a), eq(div(r, a), b))) { panic(0x11) }
            }
            function safeDiv(a, b) -> r {
                if iszero(b) { panic(0x12) }
                r := div(a, b)
            }
            function panic(code) {
                mstore(0x00, shl(224, 0x4e487b71)) // Panic(uint256)
                mstore(0x04, code)
                revert(0x00, 0x24)
            }
        }
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        assembly {
            if eq(tokenAddress, sload(stakingToken.slot)) {
                mstore(0x00, shl(224, 0x08c379a0)) // Error(string)
                mstore(0x04, 0x20) // offset
                mstore(0x24, 29) // length
                mstore(0x44, "Cannot withdraw staking token")
                revert(0x00, 0x64)
            }
        }

        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);

        assembly {
            mstore(0x00, "Recovered(address,uint256)")
            let top1 := keccak256(0x00, 26)
            mstore(0x00, tokenAddress)
            mstore(0x20, tokenAmount)
            log1(0x00, 0x40, top1)
        }
    }

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