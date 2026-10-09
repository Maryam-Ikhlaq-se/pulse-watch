#!/bin/bash

THRESHOLD=80
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
