#!/bin/bash
# Unit tests for the alert logic. Time is faked, so no waiting is needed.
PASS=0
FAIL=0

check() {
    if [[ "$2" == "$3" ]]; then
        echo "PASS: $1"; PASS=$((PASS+1))
    else
        echo "FAIL: $1 (expected $2, got $3)"; FAIL=$((FAIL+1))
    fi
}

# Load the functions without starting the monitoring loop
source ./monitor.sh
LOG_FILE=/dev/null
COOLDOWN=60

OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT

# Replace the real clock with a fake one we control
FAKE_NOW=1000
now_epoch() { echo "$FAKE_NOW"; }

count() { grep -c "$1" "$OUT"; }

# --- One metric through a full incident ---
FAKE_NOW=1000; check_metric MEM 50 10 >> "$OUT"
check "first HIGH sends one alert" 1 "$(count 'ALERT: MEM HIGH')"

FAKE_NOW=1030; check_metric MEM 50 10 >> "$OUT"
check "still HIGH inside cooldown sends nothing new" 1 "$(count 'ALERT: MEM HIGH')"
check "no reminder inside cooldown" 0 "$(count 'STILL HIGH: MEM')"

FAKE_NOW=1061; check_metric MEM 50 10 >> "$OUT"
check "reminder after cooldown" 1 "$(count 'STILL HIGH: MEM')"

FAKE_NOW=1090; check_metric MEM 50 10 >> "$OUT"
check "cooldown restarts after a reminder" 1 "$(count 'STILL HIGH: MEM')"

FAKE_NOW=1100; check_metric MEM 5 10 >> "$OUT"
check "recovery message sent" 1 "$(count 'RECOVERED: MEM')"

FAKE_NOW=1105; check_metric MEM 5 10 >> "$OUT"
check "recovery message sent only once" 1 "$(count 'RECOVERED: MEM')"

FAKE_NOW=1110; check_metric MEM 50 10 >> "$OUT"
check "new incident after recovery alerts again" 2 "$(count 'ALERT: MEM HIGH')"

# --- Metrics are tracked separately ---
FAKE_NOW=1111; check_metric CPU 50 10 >> "$OUT"
check "CPU alerts independently of MEM" 1 "$(count 'ALERT: CPU HIGH')"

FAKE_NOW=1112; check_metric DISK 1 90 >> "$OUT"
check "normal reading sends no alert" 0 "$(count 'ALERT: DISK')"
check "normal reading sends no recovery" 0 "$(count 'RECOVERED: DISK')"

# --- Message content ---
check "alert names the server" 1 "$(grep -c "Server: $(hostname)" <<< "$(build_alert ALERT CPU 50 10)")"
check "alert says what to check first" 1 "$(grep -c 'Check first:' <<< "$(build_alert ALERT CPU 50 10)")"
check "alert shows value against limit" 1 "$(grep -c 'CPU: 50% (limit 10%)' <<< "$(build_alert ALERT CPU 50 10)")"

echo "Passed: $PASS, Failed: $FAIL"
[[ $FAIL -eq 0 ]]
