#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SNAP_FILE="${SNAP_FILE:-/tmp/staking-rewards.gas-snapshot}"
MATCH_PATH="${MATCH_PATH:-test/StakingRewardsComparison.t.sol}"
MATCH_TEST="${MATCH_TEST:-testGas_.*}"
RUN_TESTS_FIRST="${RUN_TESTS_FIRST:-1}"

FORGE_FLAGS=()
if [[ "${FORGE_OFFLINE:-1}" == "1" ]]; then
  FORGE_FLAGS+=(--offline)
fi

if [[ "$RUN_TESTS_FIRST" == "1" ]]; then
  echo "Running tests: $MATCH_PATH"
  forge test "${FORGE_FLAGS[@]}" --match-path "$MATCH_PATH"
  echo
fi

echo "Collecting gas snapshot diff from: $MATCH_TEST"
forge snapshot "${FORGE_FLAGS[@]}" \
  --match-path "$MATCH_PATH" \
  --match-test "$MATCH_TEST" \
  --snap "$SNAP_FILE" >/dev/null

echo
echo "## Gas Diff (Legacy vs Yul)"
echo
sed -nE 's/.*testGas_([A-Za-z0-9]+)_([A-Za-z]+)\(\) \(gas: ([0-9]+)\).*/\1,\2,\3/p' "$SNAP_FILE" | awk -F',' '
function fmt(n,    s,neg,i,ch,out,c) {
  neg = (n < 0)
  if (neg) n = -n
  s = sprintf("%d", n)
  out = ""
  c = 0
  for (i = length(s); i > 0; i--) {
    ch = substr(s, i, 1)
    out = ch out
    c++
    if (c % 3 == 0 && i > 1) out = "," out
  }
  if (neg) out = "-" out
  return out
}

{
  op = $1
  impl = $2
  gas[op, impl] = $3 + 0
}

END {
  split("Deploy NotifyRewardAmount Stake Withdraw GetReward Exit", order, " ")
  rows = 0

  print "| Function | Legacy Gas | Yul Gas | Delta (Legacy-Yul) | Yul Savings |"
  print "|---|---:|---:|---:|---:|"

  for (i = 1; i <= length(order); i++) {
    op = order[i]
    legacy = gas[op, "Legacy"]
    yul = gas[op, "Yul"]
    if (legacy == 0 && yul == 0) continue

    delta = legacy - yul
    pct = (legacy > 0) ? (100.0 * delta / legacy) : 0

    printf("| `%s` | %s | %s | %s | %.2f%% |\n", op, fmt(legacy), fmt(yul), fmt(delta), pct)
    rows++

    totalLegacy += legacy
    totalYul += yul
  }

  if (rows == 0) {
    print "| _No gas rows parsed_ | - | - | - | - |"
    exit 1
  }

  totalDelta = totalLegacy - totalYul
  totalPct = (totalLegacy > 0) ? (100.0 * totalDelta / totalLegacy) : 0

  printf("| **Total** | %s | %s | %s | %.2f%% |\n", fmt(totalLegacy), fmt(totalYul), fmt(totalDelta), totalPct)
}
'
