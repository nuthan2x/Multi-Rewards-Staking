//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title StakingMultiRewards
/// @notice Synthetix StakingRewards adapted for multiple reward tokens.
///         Reward tokens are append-only — once added, they remain in the set permanently
///         to prevent reward accounting desync on stake/withdraw.
/// @dev Gas cost of updateRewards scales linearly with reward token count. Keep the set small.
contract StakingMultiRewards is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 private constant WAD = 1e18;

    /* ========== STATE VARIABLES ========== */

    IERC20 public stakingToken;
    EnumerableSet.AddressSet private _rewardsTokens;

    /// @dev Stored as WAD-scaled (tokens per second * 1e18) to preserve precision for
    ///      small reward amounts or long durations that would otherwise truncate to zero.
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

    /// @param owner Contract owner (receives Ownable admin rights).
    /// @param _stakingToken ERC20 token users deposit to earn rewards. Cannot be address(0).
    /// @param _rewardsDistribution Address authorized to call notifyRewardAmount. Cannot be address(0).
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

    /// @notice Number of registered reward tokens.
    function getRewardsTokensCount() external view returns (uint256) {
        return _rewardsTokens.length();
    }

    /// @notice All registered reward token addresses.
    /// @dev Allocates a memory array — avoid calling on-chain in gas-sensitive paths.
    function getRewardsTokens() external view returns (address[] memory) {
        return _rewardsTokens.values();
    }

    /// @notice Reward token address at `index`.
    /// @dev Reverts if index >= length.
    function getRewardsToken(uint256 index) external view returns (address) {
        return _rewardsTokens.at(index);
    }

    /// @notice Whether `rewardToken` is a registered reward token.
    function isRewardsToken(address rewardToken) external view returns (bool) {
        return _rewardsTokens.contains(rewardToken);
    }

    /// @notice Latest timestamp at which rewards are still accruing for `rewardToken`.
    /// @return min(block.timestamp, periodFinish) — returns 0 if never notified.
    function lastTimeRewardApplicable(address rewardToken) public view returns (uint256) {
        return block.timestamp < periodFinish[rewardToken] ? block.timestamp : periodFinish[rewardToken];
    }

    /// @notice Cumulative reward per staked token (WAD-scaled).
    /// @dev rewardRate is already WAD-scaled, so no extra `* WAD` here.
    ///      When totalSupply == 0, returns the last stored snapshot (rewards accrue to no one).
    function rewardPerToken(address rewardToken) public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored[rewardToken];
        }
        return
            rewardPerTokenStored[rewardToken] +
                (lastTimeRewardApplicable(rewardToken) - lastUpdateTime[rewardToken]) * rewardRate[rewardToken] / totalSupply;
    }

    /// @notice Pending reward amount for `account` denominated in `rewardToken`.
    function earned(address account, address rewardToken) public view returns (uint256) {
        return 
            rewards[account][rewardToken] + 
                (balances[account] * (rewardPerToken(rewardToken) - userRewardPerTokenPaid[account][rewardToken]) / WAD);
    }

    /// @notice Total reward distributed over the full rewardsDuration at current rate.
    /// @dev Unscales the WAD-scaled rewardRate back to raw token amount.
    function getRewardForDuration(address rewardToken) external view returns (uint256) {
        return rewardRate[rewardToken] * rewardsDuration[rewardToken] / WAD;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Deposit `amount` of stakingToken to begin earning rewards.
    /// @dev Caller must have approved this contract. Reverts if amount == 0.
    function stake(uint256 amount) external nonReentrant whenNotPaused updateRewards(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        totalSupply += amount;
        balances[msg.sender] += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    /// @notice Withdraw `amount` of stakingToken. Does not claim rewards — use exit() for both.
    /// @dev Reverts on underflow if amount > balance.
    function withdraw(uint256 amount) public nonReentrant updateRewards(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        totalSupply -= amount;
        balances[msg.sender] -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Claim accrued rewards for every registered reward token.
    function getAllRewards() external updateRewards(msg.sender) {
        for (uint256 i = 0; i < _rewardsTokens.length(); i++) {
            address rewardToken = _rewardsTokens.at(i);            
            _getReward(rewardToken);
        }
    }

    /// @notice Claim accrued rewards for a single `rewardToken`.
    /// @dev Works for any token (active or finished period). No-op if reward == 0.
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

    /// @notice Withdraw full balance and claim all rewards in one call.
    /// @dev Rewards are checkpointed inside withdraw's updateRewards modifier.
    function exit() external {
        withdraw(balances[msg.sender]);
        
        for (uint256 i = 0; i < _rewardsTokens.length(); i++) {
            address rewardToken = _rewardsTokens.at(i);
            _getReward(rewardToken);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice Start or top-up a reward period for `rewardToken`.
    /// @dev rewardRate is stored WAD-scaled for precision. If called mid-period,
    ///      leftover rewards roll into the new period. Caller must transfer reward
    ///      tokens to this contract beforehand.
    ///      Reverts if contract balance can't sustain the computed rewardRate.
    /// @param rewardToken Must already be registered via addRewardToken.
    /// @param reward Total reward amount (raw, not WAD-scaled) to distribute over rewardsDuration.
    function notifyRewardAmount(address rewardToken, uint256 reward) external onlyRewardsDistribution updateRewards(address(0)) {
        require(_rewardsTokens.contains(rewardToken), "rewardToken not added");

        if (block.timestamp >= periodFinish[rewardToken]) {
            rewardRate[rewardToken] = reward * WAD / rewardsDuration[rewardToken];
        } else {
            uint256 leftOver = rewardRate[rewardToken] * (periodFinish[rewardToken] - block.timestamp) / WAD;
            rewardRate[rewardToken] = (reward + leftOver) * WAD / rewardsDuration[rewardToken];
        }

        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        require(rewardRate[rewardToken] <= balance * WAD / rewardsDuration[rewardToken], "Provided reward too high");

        lastUpdateTime[rewardToken] = block.timestamp;
        periodFinish[rewardToken] = block.timestamp + rewardsDuration[rewardToken];
        emit RewardAdded(rewardToken, reward);
    }

    /// @notice Recover ERC20 tokens accidentally sent to this contract.
    /// @dev Cannot recover stakingToken or any registered reward token.
    ///      If excess reward tokens were sent, use a smaller `reward` input in the next
    ///      notifyRewardAmount() — the balance check already accounts for the full balance.
    /// @param tokenAddress ERC20 to recover. Must not be stakingToken or a reward token.
    /// @param tokenAmount Amount to transfer to owner.
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(stakingToken), "Cannot withdraw the staking token");
        require(!_rewardsTokens.contains(tokenAddress), "Cannot withdraw a reward token");
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /// @notice Update the vesting duration for a reward token. Only callable after current period ends.
    /// @param rewardToken Must already be registered via addRewardToken.
    /// @param _rewardsDuration New duration in seconds. Must be > 0.
    function setRewardsDuration(address rewardToken, uint256 _rewardsDuration) external onlyOwner {
        require(_rewardsTokens.contains(rewardToken), "rewardToken not added");
        require(block.timestamp > periodFinish[rewardToken], "rewards are still streaming");

        require(_rewardsDuration != 0, "stream rewards atleast a second");
        rewardsDuration[rewardToken] = _rewardsDuration;
        emit RewardsDurationUpdated(rewardToken, _rewardsDuration);
    }

    /// @notice Replace the rewardsDistribution address.
    function setRewardsDistribution(address _rewardsDistribution) external onlyOwner {
        rewardsDistribution = _rewardsDistribution;
    }

    /// @notice Pause staking. Withdrawals and reward claims remain enabled.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause staking.
    function unPause() external onlyOwner {
        _unpause();
    }

    /// @notice Register a new reward token. Append-only — cannot be removed.
    /// @dev Do not add stakingToken as a reward token; balanceOf check in notifyRewardAmount
    ///      would include staked deposits, inflating the allowed rewardRate.
    /// @param rewardToken ERC20 address. Must not be address(0) or already registered.
    /// @param _rewardsDuration Vesting duration in seconds. Must be > 0.
    function addRewardToken(address rewardToken, uint256 _rewardsDuration) external onlyOwner updateRewards(address(0)) {
        require(!_rewardsTokens.contains(rewardToken), "rewardToken already added");
        require(rewardToken != address(0), "rewardToken can't be address(0)");
        require(_rewardsDuration != 0, "stream rewards atleast a second");

        _rewardsTokens.add(rewardToken);
        rewardsDuration[rewardToken] = _rewardsDuration;
        emit RewardTokenAdded(rewardToken, _rewardsDuration);
    }

    /* ========== MODIFIERS ========== */

    modifier onlyRewardsDistribution() {
        require(msg.sender == rewardsDistribution, "Caller is not RewardsDistribution contract");
        _;
    }

    /// @dev Snapshots global accumulators and (if user != address(0)) per-user reward state
    ///      for every registered reward token. Called before any balance-mutating operation.
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
    event RewardsDurationUpdated(address indexed rewardToken, uint256 rewardsDuration);
    event RewardAdded(address indexed rewardToken, uint256 reward);

}
