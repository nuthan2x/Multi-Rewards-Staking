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
        address _rewardsDistribution
    ) Ownable(owner) {
        require(address(_stakingToken) != address(0), "_stakingToken can't be address(0)");
        require(_rewardsDistribution != address(0), "_rewardsDistribution can't be address(0)");

        stakingToken = _stakingToken;
        rewardsDistribution = _rewardsDistribution;
    }

    /* ========== VIEWS ========== */

    function getRewardsTokensCount() external view returns (uint256) {
        return _rewardsTokens.length();
    }

    function getRewardsTokens() external view returns (address[] memory) {
        return _rewardsTokens.values();
    }
    
    function getRewardsToken(uint256 index) external view returns (address) {
        return _rewardsTokens.at(index);
    }

    function isRewardsToken(address rewardToken) external view returns (bool) {
        return _rewardsTokens.contains(rewardToken);
    }

    function lastTimeRewardApplicable(address rewardToken) public view returns (uint256) {
        return block.timestamp < periodFinish[rewardToken] ? block.timestamp : periodFinish[rewardToken];
    }

    function rewardPerToken(address rewardToken) public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored[rewardToken];
        }
        return
            rewardPerTokenStored[rewardToken] +
                (lastTimeRewardApplicable(rewardToken) - lastUpdateTime[rewardToken]) * rewardRate[rewardToken] * WAD / totalSupply;
    }

    function earned(address account, address rewardToken) public view returns (uint256) {
        return 
            rewards[account][rewardToken] + 
                (balances[account] * (rewardPerToken(rewardToken) - userRewardPerTokenPaid[account][rewardToken]) / WAD);
    }

    function getRewardForDuration(address rewardToken) external view returns (uint256) {
        return rewardRate[rewardToken] * rewardsDuration[rewardToken];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount) external nonReentrant whenNotPaused updateRewards(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        totalSupply += amount;
        balances[msg.sender] += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateRewards(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        totalSupply -= amount;
        balances[msg.sender] -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getAllRewards() external updateRewards(msg.sender) {
        for (uint256 i = 0; i < _rewardsTokens.length(); i++) {
            address rewardToken = _rewardsTokens.at(i);            
            _getReward(rewardToken);
        }
    }

    function getReward(address rewardToken) external updateRewards(msg.sender) {         
        _getReward(rewardToken);
    }

    function _getReward(address rewardToken) private nonReentrant {
        uint256 reward = rewards[msg.sender][rewardToken];
        if (reward > 0) {
            rewards[msg.sender][rewardToken] = 0;
            IERC20(rewardToken).safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, rewardToken, reward);
        }
    }

    function exit() external {
        withdraw(balances[msg.sender]);
        
        for (uint256 i = 0; i < _rewardsTokens.length(); i++) {
            address rewardToken = _rewardsTokens.at(i);
            _getReward(rewardToken);
        }
    }

    function getRemovedTokenRewards(address[] memory removedRewardTokens) external nonReentrant {
        for (uint256 i = 0; i < removedRewardTokens.length; i++) {
            address rewardToken = removedRewardTokens[i];

            require(!_rewardsTokens.contains(rewardToken), "rewardToken already added");
            require(rewardPerTokenStored[rewardToken] != 0, "rewards never streamed");

            uint256 reward = earned(msg.sender, rewardToken);
            require(reward > 0, "no rewards");

            rewards[msg.sender][rewardToken] = 0;
            userRewardPerTokenPaid[msg.sender][rewardToken] = rewardPerTokenStored[rewardToken];

            IERC20(rewardToken).safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, rewardToken, reward);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // @todo scale reward rate by WAD always
    function notifyRewardAmount(address rewardToken, uint256 reward) external onlyRewardsDistribution updateRewards(address(0)) {
        require(_rewardsTokens.contains(rewardToken), "rewardToken not added");

        if (block.timestamp >= periodFinish[rewardToken]) {
            rewardRate[rewardToken] = reward / rewardsDuration[rewardToken];
        } else {
            uint256 leftOver = rewardRate[rewardToken] * (periodFinish[rewardToken] - block.timestamp);
            rewardRate[rewardToken] = (reward + leftOver) / rewardsDuration[rewardToken];
        }

        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        require(rewardRate[rewardToken] <= balance / rewardsDuration[rewardToken], "Provided reward too high");

        lastUpdateTime[rewardToken] = block.timestamp;
        periodFinish[rewardToken] = block.timestamp + rewardsDuration[rewardToken];
        emit RewardAdded(rewardToken, reward);
    }

    // Added to support recovering LP Rewards from other systems 
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(stakingToken), "Cannot withdraw the staking token");
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function setRewardsDuration(address rewardToken, uint256 _rewardsDuration) external onlyOwner {
        require(_rewardsTokens.contains(rewardToken), "rewardToken not added");
        require(block.timestamp > periodFinish[rewardToken], "rewards are still streaming");

        require(_rewardsDuration != 0, "stream rewards atleast a second");
        rewardsDuration[rewardToken] = _rewardsDuration;
        emit RewardsDurationUpdated(rewardToken, _rewardsDuration);
    }

    function setRewardsDistribution(address _rewardsDistribution) external onlyOwner {
        rewardsDistribution = _rewardsDistribution;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unPause() external onlyOwner {
        _unpause();
    }

    function addRewardToken(address rewardToken, uint256 _rewardsDuration) external onlyOwner updateRewards(address(0)) {
        require(!_rewardsTokens.contains(rewardToken), "rewardToken already added");
        require(rewardToken != address(0), "rewardToken can't be address(0)");
        require(_rewardsDuration != 0, "stream rewards atleast a second");

        _rewardsTokens.add(rewardToken);
        rewardsDuration[rewardToken] = _rewardsDuration;
        emit RewardTokenAdded(rewardToken, _rewardsDuration);
    }

    // @todo test add rem , if rewards claimable?
    // @todo test add rem add flow, if rewards claimable?
    // @todo test add rem add remove flow, if rewards claimable?
    function removeRewardToken(address rewardToken) external onlyOwner updateRewards(address(0)) {
        require(_rewardsTokens.contains(rewardToken), "rewardToken not added");
        require(block.timestamp > periodFinish[rewardToken], "rewards are still streaming");

        _rewardsTokens.remove(rewardToken);
        emit RewardTokenRemoved(rewardToken);
    }

    /* ========== MODIFIERS ========== */

    modifier onlyRewardsDistribution() {
        require(msg.sender == rewardsDistribution, "Caller is not RewardsDistribution contract");
        _;
    }

    modifier updateRewards(address user) {
        for (uint256 i = 0; i < _rewardsTokens.length(); i++) {
            address rewardToken = _rewardsTokens.at(i);

            rewardPerTokenStored[rewardToken] = rewardPerToken(rewardToken);
            lastUpdateTime[rewardToken] = lastTimeRewardApplicable(rewardToken);

            if(user != address(0)) {
                rewards[user][rewardToken] = earned(user, rewardToken);
                userRewardPerTokenPaid[user][rewardToken] = rewardPerTokenStored[rewardToken];
            }           
        }
        _;
    }


    /* ========== EVENTS ========== */
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, address indexed rewardToken, uint256 reward);
    event Recovered(address token, uint256 amount);
    event RewardTokenAdded(address indexed rewardToken, uint256 rewardsDuration);
    event RewardTokenRemoved(address indexed rewardToken);
    event RewardsDurationUpdated(address indexed rewardToken, uint256 rewardsDuration);
    event RewardAdded(address indexed rewardToken, uint256 reward);

}
