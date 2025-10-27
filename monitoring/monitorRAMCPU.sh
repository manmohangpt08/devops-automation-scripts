#!/bin/bash

# Set thresholds for RAM and CPU usage
RAM_THRESHOLD=90
CPU_THRESHOLD=90
EMAIL="<ALERT_EMAIL_ADDRESS>"

# Temp files to track consecutive high usage counts
RAM_CHECK_FILE="/home/opc/monitoring/ram_check_count"
CPU_CHECK_FILE="/home/opc/monitoring/cpu_check_count"

# Get total and used memory
TOTAL_MEM=$(free -m | awk '/Mem:/ {print $2}')
USED_MEM=$(free -m | awk '/Mem:/ {print $3}')
MEM_PERCENT=$(( 100 * USED_MEM / TOTAL_MEM ))

# Get total CPU usage (user + system)
CPU_PERCENT=$(top -bn1 | awk '/^%Cpu/ {print $2 + $4}')

# Read previous check counts (default to 0)
[[ -f "$RAM_CHECK_FILE" ]] && RAM_COUNT=$(cat "$RAM_CHECK_FILE") || RAM_COUNT=0
[[ -f "$CPU_CHECK_FILE" ]] && CPU_COUNT=$(cat "$CPU_CHECK_FILE") || CPU_COUNT=0

# Check RAM usage
if [ "$MEM_PERCENT" -gt "$RAM_THRESHOLD" ]; then
    RAM_COUNT=$((RAM_COUNT + 1))
    echo "$RAM_COUNT" > "$RAM_CHECK_FILE"
else
    echo "0" > "$RAM_CHECK_FILE"
    RAM_COUNT=0
fi

# Check CPU usage
CPU_INT=${CPU_PERCENT%.*}  # Convert float to integer
if [ "$CPU_INT" -gt "$CPU_THRESHOLD" ]; then
    CPU_COUNT=$((CPU_COUNT + 1))
    echo "$CPU_COUNT" > "$CPU_CHECK_FILE"
else
    echo "0" > "$CPU_CHECK_FILE"
    CPU_COUNT=0
fi

# If RAM or CPU is above threshold for 2 consecutive checks, send alert
if [ "$RAM_COUNT" -ge 2 ] || [ "$CPU_COUNT" -ge 2 ]; then
    # Get top memory-consuming processes
    TOP_MEM_PROCESSES=$(ps -eo pid,comm,%mem --sort=-%mem | head -n 10)

    # Get top CPU-consuming processes
    TOP_CPU_PROCESSES=$(ps -eo pid,comm,%cpu --sort=-%cpu | head -n 10)

    # Create the email message
    MESSAGE="🚨 Alert: High System Resource Usage 🚨\n
    Total Memory: ${TOTAL_MEM}MB\n
    Used Memory: ${USED_MEM}MB (${MEM_PERCENT}%)\n
    CPU Usage: ${CPU_PERCENT}%\n
    \n🔥 Top Memory Consuming Processes:\n
    PID   Process   Memory%\n
    $TOP_MEM_PROCESSES\n
    \n⚡ Top CPU Consuming Processes:\n
    PID   Process   CPU%\n
    $TOP_CPU_PROCESSES"

    # Send the email alert
    echo -e "$MESSAGE" | mail -s "🚨 High CPU/RAM Alert 🚨" "$EMAIL"

    # Reset both check counts after sending an alert
    echo "0" > "$RAM_CHECK_FILE"
    echo "0" > "$CPU_CHECK_FILE"
fi
