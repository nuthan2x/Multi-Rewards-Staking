//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @notice multiple reward tokens flexibility
/// @notice no safemath needed ^0.8.0 compiler
/// @notice Rewriting `synthetix/contracts/StakingRewards.sol` in 0.8.0 compiler version with latest openzeppelin lib
contract StakingMultiRewards is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 private constant WAD = 1e18;

    /* ========== STATE VARIABLES ========== */

    IERC20 public stakingToken;
    EnumerableSet.AddressSet private _rewardsTokens;

    mapping(address rewardToken => uint256) public rewardRate;
    mapping(address rewardToken => uint256) public rewardPerTokenStored;

    mapping(address rewardToken => uint256) public rewardsDuration;
    mapping(address rewardToken => uint256) public periodFinish;
    mapping(address rewardToken => uint256) public lastUpdateTime;

    mapping(address user => mapping(address rewardToken => uint256)) public userRewardPerTokenPaid;
    mapping(address user => mapping(address rewardToken => uint256)) public rewards;

    uint256 public totalSupply;
    mapping(address user => uint256) public balances;

    address public rewardsDistribution;


    /* ========== CONSTRUCTOR ========== */

    constructor(
        address owner, 
        IERC20 _stakingToken, 
        uint256 _rewardsDuration
    ) Ownable(owner) {
        require(address(_stakingToken) != address(0), "_stakingToken can't be address(0)");
        require(_rewardsDistribution != address(0), "_rewardsDistribution can't be address(0)");

        stakingToken = _stakingToken;
        rewardsDistribution = _rewardsDistribution;
    }

}
