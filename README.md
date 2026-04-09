## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Gas Diff (Legacy vs Yul)

| Function | Legacy Gas | Yul Gas | Delta (Legacy-Yul) | Yul Savings |
|---|---:|---:|---:|---:|
| `Deploy` | 2,207,463 | 1,507,024 | 700,439 | 31.73% |
| `NotifyRewardAmount` | 75,386 | 74,714 | 672 | 0.89% |
| `Stake` | 83,921 | 82,988 | 933 | 1.11% |
| `Withdraw` | 77,345 | 75,633 | 1,712 | 2.21% |
| `GetReward` | 78,637 | 76,564 | 2,073 | 2.64% |
| `Exit` | 83,330 | 80,633 | 2,697 | 3.24% |
| **Total** | 2,606,082 | 1,897,556 | 708,526 | 27.19% |

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Run The Gas Comparison Yourself

```shell
$ chmod +x gas-compare.sh
$ ./gas-compare.sh
```

This prints a markdown table for the paired tests in `test/StakingRewardsComparison.t.sol`:

- `testGas_Deploy_Legacy` vs `testGas_Deploy_Yul`
- `testGas_NotifyRewardAmount_Legacy` vs `testGas_NotifyRewardAmount_Yul`
- `testGas_Stake_Legacy` vs `testGas_Stake_Yul`
- `testGas_Withdraw_Legacy` vs `testGas_Withdraw_Yul`
- `testGas_GetReward_Legacy` vs `testGas_GetReward_Yul`
- `testGas_Exit_Legacy` vs `testGas_Exit_Yul`

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
