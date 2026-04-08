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