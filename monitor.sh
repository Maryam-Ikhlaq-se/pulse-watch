#!/bin/bash

THRESHOLD="${1:-80}"
if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]] || (( 10#$THRESHOLD < 1 || 10#$THRESHOLD > 100)); then
	echo "Error: threshold must be a whole number from 1 to 100." >&2
	echo "Usage: $0 [threshold]" >&2
	exit 1
fi

if ! command -v bc >/dev/null 2>&1; then
       echo "Error: 'bc' is required. Install it with: sudo apt insatll bc" >&2
       exit 1
fi

INTERVAL=5

while true;do

     CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{print 100 - $1}')

     if (( $(echo "$CPU_USAGE > $THRESHOLD" | bc -l) )); then
           echo "CPU: ${CPU_USAGE}% - HIGH"
     else
           echo "CPU: ${CPU_USAGE}% - NORMAL"
     fi

     sleep "$INTERVAL"

done
