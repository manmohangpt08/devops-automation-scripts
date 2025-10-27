#!/bin/bash
for pid in $(ls /proc/ | grep -E '^[0-9]+$'); do
    name=$(awk -v pid=$pid '$1 == "Name:" {print $2}' /proc/$pid/status)
    swap=$(awk -v pid=$pid '$1 == "VmSwap:" {print $2}' /proc/$pid/status)
    swap_mb=$((swap / 1024))  # Convert swap from KB to MB
    if [ -n "$name" ]; then
        printf "%-10s %-15s %10s MB\n" "$pid" "$name" "$swap_mb"
    fi
done | sort -k 3 -n -r | less
