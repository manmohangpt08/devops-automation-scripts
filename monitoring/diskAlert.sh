#!/bin/bash

# --- CONFIGURATION ---
THRESHOLD=85
EMAIL=<NOTIFICATION_EMAIL_ADDRESS>
DISK_PART="/"
LOG_FILE="disk_alert_log.txt"
DATE=$(date +%Y-%m-%d)
HOSTNAME=$(hostname)
SUBJECT="[ALERT] Disk Usage Critical on $HOSTNAME"

# --- CHECK DISK USAGE ---
USAGE=$(df -P | awk -v part="$DISK_PART" '$6 == part {gsub("%","",$5); print $5}' | tr -d '[:space:]')
THRESHOLD=$(echo "$THRESHOLD" | tr -d '[:space:]')

# Debug lines
echo "DEBUG: USAGE='$USAGE'"
echo "DEBUG: THRESHOLD='$THRESHOLD'"

# Ensure we got a value
if [ -z "$USAGE" ]; then
    echo "Failed to detect disk usage for $DISK_PART" >&2
    exit 1
fi

# --- IF USAGE EXCEEDS THRESHOLD ---
if [ "$USAGE" -ge "$THRESHOLD" ]; then
    if [ -f "$LOG_FILE" ]; then
        ALERT_COUNT=$(grep -c "$DATE" "$LOG_FILE")
    else
        ALERT_COUNT=0
    fi

    if [ "$ALERT_COUNT" -lt 2 ]; then
        TMP_FILE="disk_usage_report.txt"

        {
            echo "Date: $(date)"
            echo "Server: $HOSTNAME"
            echo "Disk usage on $DISK_PART is ${USAGE}%"
            echo ""
            echo "Top 10 largest directories in /:"
            du -ahx --max-depth=1 / 2>/dev/null | sort -rh | head -n 10
            echo ""
            echo "Top 10 largest files in /:"
            find / -xdev -type f -exec du -h {} + 2>/dev/null | sort -rh | head -n 10
        } > "$TMP_FILE"

        # Send email with report
        echo "High disk usage" | mail -s "$SUBJECT" "$EMAIL" < "$TMP_FILE"   

        # Log the alert
        echo "$DATE Alert sent for $HOSTNAME at $(date +%H:%M)" >> "$LOG_FILE"
    fi
fi
