#!/bin/bash

THRESHOLD="${1:-80}"

if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]] || (( 10#$THRESHOLD < 1 || 10#$THRESHOLD > 100 )); then
    echo "Error: threshold must be a whole number from 1 to 100." >&2
    echo "Usage: $0 [threshold]" >&2
    exit 1
fi

if ! command -v bc >/dev/null 2>&1; then
    echo "Error: 'bc' is required. Install it with: sudo apt install bc" >&2
    exit 1
fi

INTERVAL=5
LOG_FILE="pulsewatch.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

get_cpu() {
    top -bn1 | grep "Cpu(s)" | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{print 100 - $1}'
}

get_memory() {
    free | awk '/Mem:/ {printf "%.1f", $3/$2*100}'
}

while true; do
    CPU_USAGE=$(get_cpu)
    MEM_USAGE=$(get_memory)

    if (( $(echo "$CPU_USAGE > $THRESHOLD" | bc -l) )); then
        log "CPU: ${CPU_USAGE}% - HIGH"
    else
        log "CPU: ${CPU_USAGE}% - NORMAL"
    fi

    log "MEM: ${MEM_USAGE}%"

    sleep "$INTERVAL"
done
