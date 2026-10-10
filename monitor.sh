#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${PULSEWATCH_CONF:-$SCRIPT_DIR/pulsewatch.conf}"

# Defaults, used when the config file is missing or leaves a value out
CPU_LIMIT=80
MEM_LIMIT=80
DISK_LIMIT=90
INTERVAL=5
COOLDOWN=300
LOG_FILE="pulsewatch.log"

validate_limit() {
    local name="$1" value="$2"
    if ! [[ "$value" =~ ^[0-9]+$ ]] || (( 10#$value < 1 || 10#$value > 100 )); then
        echo "Error: $name must be a whole number from 1 to 100 (got '$value')." >&2
        echo "Usage: $0 [threshold]" >&2
        exit 1
    fi
}

validate_seconds() {
    local name="$1" value="$2"
    if ! [[ "$value" =~ ^[0-9]+$ ]] || (( 10#$value < 1 )); then
        echo "Error: $name must be a whole number of seconds, 1 or more (got '$value')." >&2
        exit 1
    fi
}

# 1. Load the config file (overrides defaults)
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# 2. A command-line threshold overrides every limit
if [[ -n "$1" ]]; then
    validate_limit "threshold" "$1"
    CPU_LIMIT="$1"
    MEM_LIMIT="$1"
    DISK_LIMIT="$1"
fi

# 3. Validate the final values
validate_limit "CPU_LIMIT" "$CPU_LIMIT"
validate_limit "MEM_LIMIT" "$MEM_LIMIT"
validate_limit "DISK_LIMIT" "$DISK_LIMIT"
validate_seconds "INTERVAL" "$INTERVAL"
validate_seconds "COOLDOWN" "$COOLDOWN"

if ! command -v bc >/dev/null 2>&1; then
    echo "Error: 'bc' is required. Install it with: sudo apt install bc" >&2
    exit 1
fi

# Alert state, kept in memory for each metric (CPU, MEM, DISK)
declare -A METRIC_STATE     # "HIGH" while a problem is ongoing
declare -A INCIDENT_START   # when the current problem began (epoch seconds)
declare -A LAST_ALERT       # when we last sent a message about it (epoch seconds)

now_epoch() {
    date +%s
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

get_cpu() {
    top -bn1 | grep "Cpu(s)" | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{print 100 - $1}'
}

get_memory() {
    free | awk '/Mem:/ {printf "%.1f", $3/$2*100}'
}

get_disk() {
    df / | awk 'NR==2 {gsub("%",""); print $5}'
}

# Builds the message text. kind is ALERT, REMINDER or RECOVERED.
build_alert() {
    local kind="$1" name="$2" value="$3" limit="$4"
    local host now since action header extra
    host=$(hostname)
    now=$(date '+%Y-%m-%d %H:%M:%S')

    since=""
    if [[ -n "${INCIDENT_START[$name]}" ]]; then
        since=$(date -d "@${INCIDENT_START[$name]}" '+%H:%M:%S')
    fi

    case "$name" in
        CPU)  action="run 'top' to find the busy process" ;;
        MEM)  action="run 'ps aux --sort=-%mem | head' to find the largest process" ;;
        DISK) action="run 'du -xh / --max-depth=1 2>/dev/null | sort -h | tail' to find the biggest folders" ;;
        *)    action="check the server" ;;
    esac

    case "$kind" in
        ALERT)
            header="🔴 ALERT: $name HIGH"
            extra="Check first: $action" ;;
        REMINDER)
            header="🟠 STILL HIGH: $name"
            extra="Since: $since"$'\n'"Check first: $action" ;;
        RECOVERED)
            header="✅ RECOVERED: $name"
            extra="Was high since: $since" ;;
    esac

    printf '%s\nServer: %s\nTime: %s\n%s: %s%% (limit %s%%)\n%s\n' \
        "$header" "$host" "$now" "$name" "$value" "$limit" "$extra"
}

# Delivers the message. For now it prints; WhatsApp will replace this later.
send_alert() {
    build_alert "$@"
    echo
}

# Logs every reading, but only sends a message when something changes
# (new problem, problem still ongoing after COOLDOWN, or recovery).
check_metric() {
    local name="$1" value="$2" limit="$3"
    local now
    now=$(now_epoch)

    if (( $(echo "$value > $limit" | bc -l) )); then
        log "$name: ${value}% - HIGH"
        if [[ "${METRIC_STATE[$name]}" != "HIGH" ]]; then
            METRIC_STATE[$name]="HIGH"
            INCIDENT_START[$name]="$now"
            LAST_ALERT[$name]="$now"
            send_alert ALERT "$name" "$value" "$limit"
        elif (( now - LAST_ALERT[$name] >= COOLDOWN )); then
            LAST_ALERT[$name]="$now"
            send_alert REMINDER "$name" "$value" "$limit"
        fi
    else
        log "$name: ${value}% - NORMAL"
        if [[ "${METRIC_STATE[$name]}" == "HIGH" ]]; then
            send_alert RECOVERED "$name" "$value" "$limit"
            METRIC_STATE[$name]="OK"
            unset "INCIDENT_START[$name]"
        fi
    fi
}

main() {
    log "PulseWatch started - limits: CPU ${CPU_LIMIT}%, MEM ${MEM_LIMIT}%, DISK ${DISK_LIMIT}%, interval ${INTERVAL}s, cooldown ${COOLDOWN}s"

    while true; do
        CPU_USAGE=$(get_cpu)
        MEM_USAGE=$(get_memory)
        DISK_USAGE=$(get_disk)

        check_metric "CPU" "$CPU_USAGE" "$CPU_LIMIT"
        check_metric "MEM" "$MEM_USAGE" "$MEM_LIMIT"
        check_metric "DISK" "$DISK_USAGE" "$DISK_LIMIT"

        sleep "$INTERVAL"
    done
}

# Run the loop only when executed directly, not when sourced by a test
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
