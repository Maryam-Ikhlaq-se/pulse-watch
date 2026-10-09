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

./monitor.sh abc >/dev/null 2>&1; check "rejects text" 1 $?
./monitor.sh 0 >/dev/null 2>&1; check "rejects 0" 1 $?
./monitor.sh 101 >/dev/null 2>&1; check "rejects 101" 1 $?
./monitor.sh -5 >/dev/null 2>&1; check "rejects negative" 1 $?

out=$(timeout 3 ./monitor.sh 1)
[[ "$out" == *"MEM"*"HIGH"* ]]; check "threshold 1 gives MEM HIGH" 0 $?

out=$(timeout 3 ./monitor.sh 100)
[[ "$out" != *"HIGH"* ]]; check "threshold 100 gives no HIGH" 0 $?

echo "Passed: $PASS, Failed: $FAIL"
[[ $FAIL -eq 0 ]]
