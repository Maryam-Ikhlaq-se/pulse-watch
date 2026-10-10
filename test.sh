#!/bin/bash
PASS=0
FAIL=0

check() {
    if [[ "$2" == "$3" ]]; then
        echo "PASS: $1"; PASS=$((PASS+1))
    else
        echo "FAIL: $1 (expected $2, got $3)"; FAIL=$((FAIL+1))
    fi
}

TMP_CONF=$(mktemp)
trap 'rm -f "$TMP_CONF"' EXIT

# --- Command-line validation ---
./monitor.sh abc >/dev/null 2>&1; check "rejects text" 1 $?
./monitor.sh 0 >/dev/null 2>&1; check "rejects 0" 1 $?
./monitor.sh 101 >/dev/null 2>&1; check "rejects 101" 1 $?
./monitor.sh -5 >/dev/null 2>&1; check "rejects negative" 1 $?

# --- Threshold behaviour ---
out=$(timeout 3 ./monitor.sh 1)
grep -q "MEM:.*HIGH" <<< "$out"; check "threshold 1 gives MEM HIGH" 0 $?

out=$(timeout 3 ./monitor.sh 100)
! grep -q "HIGH" <<< "$out"; check "threshold 100 gives no HIGH" 0 $?

# --- Config file behaviour ---
printf 'CPU_LIMIT=100\nMEM_LIMIT=1\nDISK_LIMIT=100\n' > "$TMP_CONF"
out=$(PULSEWATCH_CONF="$TMP_CONF" timeout 3 ./monitor.sh)
grep -q "MEM:.*HIGH" <<< "$out" && ! grep -q "CPU:.*HIGH" <<< "$out" && ! grep -q "DISK:.*HIGH" <<< "$out"
check "config: limits are independent" 0 $?

printf 'CPU_LIMIT=abc\n' > "$TMP_CONF"
PULSEWATCH_CONF="$TMP_CONF" ./monitor.sh >/dev/null 2>&1; check "config: rejects bad value" 1 $?

printf 'CPU_LIMIT=100\nMEM_LIMIT=100\nDISK_LIMIT=100\n' > "$TMP_CONF"
out=$(PULSEWATCH_CONF="$TMP_CONF" timeout 3 ./monitor.sh 1)
grep -q "MEM:.*HIGH" <<< "$out"; check "command-line overrides config" 0 $?

out=$(PULSEWATCH_CONF=/nonexistent timeout 3 ./monitor.sh)
grep -q "CPU 80%, MEM 80%, DISK 90%" <<< "$out"; check "missing config uses defaults" 0 $?

echo "Passed: $PASS, Failed: $FAIL"
[[ $FAIL -eq 0 ]]
