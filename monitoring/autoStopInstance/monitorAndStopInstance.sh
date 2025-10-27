#!/bin/bash

ENVIRONMENT=dev

# Log file paths
EMAIL_LOG_FILE="/home/opc/orchestration/manage/system_usage_email_sent.log"
STATE_LOG_FILE="/home/opc/orchestration/manage/system_usage_state.log"

# Get current timestamp
EPOCH_NOW=$(date +%s)
DATE_NOW=$(date)

# Check if log file exists
if [ ! -f "$STATE_LOG_FILE" ]; then
  # Check system responsiveness
  for i in {1..10}; do
    curl -s localhost > /dev/null
  done
  # Initialize idle state log file
  cat <<EOF > "$STATE_LOG_FILE"
SYSTEM_IDLE_TIMESTAMP_1=0
SYSTEM_IDLE_TIMESTAMP_2=0
LAST_SYSTEM_IDLE_REASON=null
EOF

else
  echo "State Log file already exists. No action taken." >> /dev/null
fi

# Load values from state log file
LATEST_SYSTEM_IDLE_TIMESTAMP_1=$(grep "SYSTEM_IDLE_TIMESTAMP_1" "$STATE_LOG_FILE" | cut -d'=' -f2)
LATEST_SYSTEM_IDLE_TIMESTAMP_2=$(grep "SYSTEM_IDLE_TIMESTAMP_2" "$STATE_LOG_FILE" | cut -d'=' -f2)
LATEST_LAST_SYSTEM_IDLE_REASON=$(grep "LAST_SYSTEM_IDLE_REASON" "$STATE_LOG_FILE" | cut -d'=' -f2)

# Email recipient
EMAIL="<ALERT_EMAIL_ADDRESS>"

# Webserver log check
WEBSERVER_NAME=${1}
if [ "$WEBSERVER_NAME" = "nginx" ]; then
    LOG_FILE_PATH="/var/log/nginx/proxy_access.log"
elif [ "$WEBSERVER_NAME" = "httpd" ]; then
    LOG_FILE_PATH="/var/log/httpd/access_log"
else
    LOG_FILE_PATH="/dev/null"
fi

# Thresholds
CPU_IDLE_THRESHOLD=98

# RAM usage
MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
RAM_USAGE=$(( (100 * MEM_USED) / MEM_TOTAL ))

# Network connections
NET_CONNECTION_COUNT=$(ss -tun state established | wc -l)

# Disk I/O activity (sum of read+write IOPS)
DISK_IO=$(iostat -d 1 2 | awk '/^Device/ {getline; getline} {sum += $3 + $4} END {print sum}' | cut -d'.' -f1)

# Docker containers running
RUNNING_CONTAINERS_COUNT=$(docker ps -q | wc -l)

# User processes (excluding root/system)
ACTIVE_PROCESS_COUNT=$(ps -eo user,tty | awk '$1 != "root" && $2 != "?"' | wc -l)

# CPU Idle %
CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | sed 's/[^0-9.]//g' | cut -d'.' -f1)

# Webserver logs in last hour
LAST_HOUR_WEBSERVER_LOGS_COUNT=$(sudo awk -v start="$(date -d '1 hour ago' '+%d/%b/%Y:%H:%M:%S')" \
                                      -v end="$(date '+%d/%b/%Y:%H:%M:%S')" \
                                      '{
                                          logtime = substr($4, 2, 20);
                                          if (logtime >= start && logtime <= end) print
                                      }' "${LOG_FILE_PATH}" | wc -l)

# Helper functions
update_status() {
    sed -i "s/^$1=.*/$1=$2/" "$STATE_LOG_FILE"
}

update_timestamp() {
    SYSTEM_USAGE_STATE=${1}
    if [ "$SYSTEM_USAGE_STATE" -eq 0 ]; then
        if [ "$LATEST_SYSTEM_IDLE_TIMESTAMP_1" != "0" ]; then
            update_status SYSTEM_IDLE_TIMESTAMP_2 "$EPOCH_NOW"
        else
            update_status SYSTEM_IDLE_TIMESTAMP_1 "$EPOCH_NOW"
        fi
    else
        update_status SYSTEM_IDLE_TIMESTAMP_1 0
        update_status SYSTEM_IDLE_TIMESTAMP_2 0
    fi
}

send_mail() {
    SYSTEM_IDLE_REASON="$1"
    if [ "$LATEST_SYSTEM_IDLE_TIMESTAMP_1" != "0" ] && [ "$LATEST_SYSTEM_IDLE_TIMESTAMP_2" != "0" ] && \
       [ $((EPOCH_NOW - LATEST_SYSTEM_IDLE_TIMESTAMP_1)) -gt 3600 ]; then
        echo -e "Found $ENVIRONMENT system is idle from last 1 hour due to: $SYSTEM_IDLE_REASON. Shutting down now." | \
        mail -s "🚨 System Idle Alert 🚨" "$EMAIL"
        echo "$EPOCH_NOW | $DATE_NOW: Sent idle alert for reason: $SYSTEM_IDLE_REASON" >> "$EMAIL_LOG_FILE"
	rm -rf ${STATE_LOG_FILE}
	sleep 20s;
	sudo shutdown -h now
    fi
}

RAM_USAGE=${RAM_USAGE:-0}
NET_CONNECTION_COUNT=${NET_CONNECTION_COUNT:-0}
DISK_IO=${DISK_IO:-0}
ACTIVE_PROCESS_COUNT=${ACTIVE_PROCESS_COUNT:-0}
CPU_IDLE=${CPU_IDLE:-0}

# Core logic
if [ "$RAM_USAGE" -le 2 ] || [ "$DISK_IO" -eq 0 ] || [ "$ACTIVE_PROCESS_COUNT" -eq 0 ] || { [ "$NET_CONNECTION_COUNT" -eq 0 ] && [ "$CPU_IDLE" -gt "$CPU_IDLE_THRESHOLD" ]; }; then
    update_timestamp 0
    REASON="RAM_USAGE:$RAM_USAGE, NET_CONNECTION_COUNT:$NET_CONNECTION_COUNT, DISK_IO:$DISK_IO, ACTIVE_PROCESS_COUNT:$ACTIVE_PROCESS_COUNT, CPU_IDLE:$CPU_IDLE"
    update_status LAST_SYSTEM_IDLE_REASON "$REASON"
    send_mail "$REASON"
elif [ "$RUNNING_CONTAINERS_COUNT" -eq 0 ]; then
    update_timestamp 0
    REASON="RUNNING_CONTAINERS_COUNT:$RUNNING_CONTAINERS_COUNT"
    update_status LAST_SYSTEM_IDLE_REASON "$REASON"
    send_mail "$REASON"
elif [ "$LAST_HOUR_WEBSERVER_LOGS_COUNT" -eq 0 ]; then
    update_timestamp 0
    REASON="LAST_HOUR_WEBSERVER_LOGS_COUNT:$LAST_HOUR_WEBSERVER_LOGS_COUNT"
    update_status LAST_SYSTEM_IDLE_REASON "$REASON"
    send_mail "$REASON"
else
    update_timestamp 1
    update_status LAST_SYSTEM_IDLE_REASON "null"
fi
