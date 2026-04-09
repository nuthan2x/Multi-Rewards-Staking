## Gas Diff (Legacy Synthetix vs Yul StakingRewards.yul.sol)

Single-reward-token implementations comparison (not StakingMultiRewards):

| Function | Legacy Gas | Yul Gas | Yul Savings |
|---|---:|---:|---:|
| `Deploy` | 2,207,463 | 1,507,024 | 31.73% |
| `NotifyRewardAmount` | 75,386 | 74,714 | 0.89% |
| `Stake` | 83,921 | 82,988 | 1.11% |
| `Withdraw` | 77,345 | 75,633 | 2.21% |
| `GetReward` | 78,637 | 76,564 | 2.64% |
| `Exit` | 83,330 | 80,633 | 3.24% |

```shell
./gas-compare.sh
```


# StakingMultiRewards

Synthetix [StakingRewards](https://docs.synthetix.io/contracts/source/contracts/stakingrewards) rewritten for Solidity ^0.8.20 with **multiple reward tokens** support. Uses OpenZeppelin v5 (`Ownable`, `Pausable`, `ReentrancyGuard`, `EnumerableSet`, `SafeERC20`).

## Architecture

```
┌─────────────────────────────────────────────┐
│            StakingMultiRewards               │
│                                             │
│  stakingToken ◄── stake() / withdraw()      │
│                                             │
│  rewardTokenA ──► getReward / getAllRewards  │
│  rewardTokenB ──►                           │
│  rewardTokenN ──►                           │
│                                             │
│  updateRewards modifier loops ALL tokens    │
│  on every stake/withdraw/claim/notify       │
└─────────────────────────────────────────────┘
```

Users deposit a single `stakingToken` and earn rewards denominated in one or more ERC20 reward tokens. Each reward token has its own independent `rewardRate`, `rewardsDuration`, and `periodFinish`. Reward accounting follows the Synthetix cumulative `rewardPerToken` pattern, extended per-token.

### Key Design Decision: Append-Only Reward Tokens

Reward tokens **cannot be removed** once added. The `updateRewards` modifier iterates over all registered reward tokens on every user interaction. Removing a token would desync `userRewardPerTokenPaid` from `balances` changes, enabling reward theft or loss. Keeping the set append-only (like [ZivoeRewards](https://github.com/sherlock-audit/2024-03-zivoe/blob/main/zivoe-core-foundry/src/ZivoeRewards.sol)) eliminates this entire class of bugs.

### WAD-Scaled `rewardRate`

`rewardRate` is stored as `tokensPerSecond * 1e18` instead of raw `tokensPerSecond`. This prevents truncation to zero for small reward amounts or long durations.

```
Original Synthetix:  rewardRate = reward / duration          → truncates small values
This contract:       rewardRate = reward * 1e18 / duration   → preserves 18 extra digits
```

The WAD factor is accounted for in `rewardPerToken` (no extra `* WAD`) and `getRewardForDuration` (divides by WAD to return raw tokens).

## Gas Scaling (1–20 Reward Tokens)

Every `stake`, `withdraw`, `getReward`, `getAllRewards`, `exit`, and `notifyRewardAmount` call triggers the `updateRewards` modifier which loops over all reward tokens.

| Tokens | `stake` | `withdraw` | `getAllRewards` | `notifyRewardAmount` |
|-------:|--------:|-----------:|----------------:|---------------------:|
| 1      | 82k     | 76k        | 39k             | 12k                  |
| 5      | 116k    | 345k       | 189k            | 25k                  |
| 10     | 158k    | 681k       | 377k            | 42k                  |
| 15     | 200k    | 1,016k     | 564k            | 58k                  |
| 20     | 242k    | 1,352k     | 752k            | 74k                  |

**Marginal cost per additional reward token:**

| Operation | Gas/token |
|-----------|----------:|
| `stake`   | ~8,400    |
| `withdraw`| ~67,200   |
| `getAllRewards` | ~37,600 |
| `notifyRewardAmount` | ~3,200 |

20 tokens is well within the 30M block gas limit. The most expensive operation (`exit` with 20 tokens) costs ~2M gas (~6.5% of the limit).

## Roles

| Role | Who | Can |
|------|-----|-----|
| **Owner** | Deployer (transferable via `Ownable`) | `addRewardToken`, `setRewardsDuration`, `setRewardsDistribution`, `recoverERC20`, `pause`, `unPause` |
| **RewardsDistribution** | Set by owner | `notifyRewardAmount` |
| **Users** | Anyone | `stake`, `withdraw`, `getReward`, `getAllRewards`, `exit` |

## Do's and Don'ts

### Do

- Transfer reward tokens to the contract **before** calling `notifyRewardAmount`. The balance check verifies the contract can sustain the rate.
- Call `setRewardsDuration` **only after** the current period ends (`block.timestamp > periodFinish`).
- Keep the reward token count low. Gas cost scales linearly.
- Use `getReward(token)` if you only care about one reward token — cheaper than `getAllRewards`.
- Use `exit()` for full withdrawal + claim in one transaction.

### Don't

- **Don't add `stakingToken` as a reward token.** The `balanceOf` check in `notifyRewardAmount` includes staked deposits, which would inflate the allowed `rewardRate`.
- **Don't assume excess reward tokens can be recovered.** `recoverERC20` blocks both `stakingToken` and all registered reward tokens. If you accidentally send excess reward tokens, account for them in the next `notifyRewardAmount` by passing a smaller `reward` amount.
- **Don't call `notifyRewardAmount` with more than the contract's balance.** It will revert with "Provided reward too high".
- **Don't expect rewards during zero-supply periods.** If no one is staked, rewards for that time window are permanently lost (accrue to no one).

## Risks

- **Owner trust.** The owner can pause staking (but not withdrawals/claims), change the rewards distributor, and recover non-staking/non-reward tokens. A malicious owner cannot steal staked tokens or reward tokens.
- **Reward token quality.** Each reward token's `safeTransfer` is called during claims. A malicious or broken ERC20 could revert, blocking claims for all tokens in `getAllRewards`/`exit`. Use `getReward(token)` to claim individual tokens if one is misbehaving.
- **Integer dust.** Division truncation means the sum of distributed rewards may be slightly less than the notified amount (typically < `rewardsDuration` wei per period). Undistributed dust remains in the contract and is absorbed by the next `notifyRewardAmount`.
- **No reward token removal.** Once added, a reward token stays in the `updateRewards` loop forever. A finished reward token with no new notifications costs only gas (the time delta is 0, so the stored value doesn't change). Plan your token list carefully.

## Function Reference

### Views

#### `getRewardsTokensCount() → uint256`
Number of registered reward tokens.

#### `getRewardsTokens() → address[]`
All registered reward token addresses. Allocates a memory array — avoid on-chain in gas-sensitive paths.

#### `getRewardsToken(uint256 index) → address`
Reward token address at `index`. Reverts if out of bounds.

#### `isRewardsToken(address rewardToken) → bool`
Whether `rewardToken` is registered.

#### `lastTimeRewardApplicable(address rewardToken) → uint256`
`min(block.timestamp, periodFinish)`. Returns 0 if never notified.

#### `rewardPerToken(address rewardToken) → uint256`
Cumulative reward per staked token (WAD-scaled). When `totalSupply == 0`, returns the last stored snapshot.

#### `earned(address account, address rewardToken) → uint256`
Pending claimable reward for `account` in `rewardToken` (raw token units).

#### `getRewardForDuration(address rewardToken) → uint256`
Total reward distributed over the full `rewardsDuration` at the current rate. Unscales the WAD-scaled `rewardRate`.

### User Actions

#### `stake(uint256 amount)`
Deposit `amount` of `stakingToken`. Caller must approve first. Reverts if `amount == 0` or paused.

#### `withdraw(uint256 amount)`
Withdraw `amount` of `stakingToken`. Does **not** claim rewards. Reverts if `amount == 0` or exceeds balance. Works when paused.

#### `getReward(address rewardToken)`
Claim accrued reward for a single token. No-op if reward is 0. Works when paused.

#### `getAllRewards()`
Claim accrued rewards for every registered reward token.

#### `exit()`
Withdraw full balance and claim all rewards in one call.

### Restricted (Owner)

#### `addRewardToken(address rewardToken, uint256 _rewardsDuration)`
Register a new reward token. Append-only. Reverts if already added, zero address, or zero duration. Do not add `stakingToken`.

#### `setRewardsDuration(address rewardToken, uint256 _rewardsDuration)`
Update vesting duration. Only callable after the current period ends. Reverts if still streaming or zero duration.

#### `setRewardsDistribution(address _rewardsDistribution)`
Replace the authorized rewards distributor address.

#### `recoverERC20(address tokenAddress, uint256 tokenAmount)`
Recover accidentally sent ERC20 tokens. Cannot recover `stakingToken` or any registered reward token.

#### `pause()` / `unPause()`
Pause/unpause staking. Withdrawals and claims remain enabled when paused.

### Restricted (RewardsDistribution)

#### `notifyRewardAmount(address rewardToken, uint256 reward)`
Start or top-up a reward period. Transfer reward tokens to the contract **before** calling. If called mid-period, leftover rewards roll into the new period. Reverts if balance can't sustain the rate.

## Events

| Event | When |
|-------|------|
| `Staked(address indexed user, uint256 amount)` | User stakes |
| `Withdrawn(address indexed user, uint256 amount)` | User withdraws |
| `RewardPaid(address indexed user, address indexed rewardToken, uint256 reward)` | User claims reward |
| `RewardAdded(address indexed rewardToken, uint256 reward)` | New reward period notified |
| `RewardTokenAdded(address indexed rewardToken, uint256 rewardsDuration)` | New reward token registered |
| `RewardsDurationUpdated(address indexed rewardToken, uint256 rewardsDuration)` | Duration changed |
| `Recovered(address token, uint256 amount)` | ERC20 recovered by owner |

## Build & Test

```shell
forge build
forge test
forge test --match-contract StakingMultiRewardsTest -vvvv   # with gas logs
```

