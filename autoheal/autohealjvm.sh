#!/bin/bash

SYSTEM_USER=opc
ENV=<ENVIRONMENT_OR_INSTANCE_NAME>
EMAIL=<ALERT_EMAIL>

if [[ -z "$ENV" || "$ENV" == "<ENVIRONMENT_OR_INSTANCE_NAME>" ]]; then
    echo "Error: ENV is not set or contains placeholder text."
    exit 1
fi

if [[ -z "$EMAIL" || "$EMAIL" == "<ALERT_EMAIL>" ]]; then
    echo "Error: EMAIL is not set or contains placeholder text."
    exit 1
fi
LOGFILE=/home/${SYSTEM_USER}/monitoring/status.log
mkdir -p /home/${SYSTEM_USER}/monitoring/
source $LOGFILE

# Function to update a value in the log file
update_status() {
    sed -i "s/^$1=.*/$1=$2/" "$LOGFILE"
    grep -q "^$1=" "$LOGFILE" || echo "$1=$2" >> "$LOGFILE"
}

check_service() {
    local service_name=$1
    local port=$2
    local systemd_service=$3

    local email_status_var="${service_name}"
    local down_since_var="${service_name}_DOWN_SINCE"
    local restarted_var="${service_name}_RESTARTED_AT"

    local email_status=${!email_status_var}
    local down_since=${!down_since_var}

    STATUS=$(curl -s --max-time 1 http://localhost:$port/ping 2>/dev/null | head -n 1 | cut -d$' ' -f2)

    if [ "$STATUS" != "OK" ]; then
        # If it's the first time it's marked down
        if [ "$email_status" != "SENT" ]; then
            echo -e "$service_name IS DOWN on $ENV" | mail -s "🚨 $service_name DOWN Alert 🚨" "$EMAIL"
            update_status "$email_status_var" "SENT"
            update_status "$down_since_var" "$(date +%s)"
        else
            # Already marked SENT, check how long it's been down
            current_time=$(date +%s)
            time_diff=$((current_time - down_since))

            if [ "$time_diff" -ge 300 ]; then
                echo "Attempting to restart $service_name ($systemd_service)_new..."
                sudo service "${systemd_service}_new" restart

                update_status "$restarted_var" "$(date '+%Y-%m-%d %H:%M:%S')"
                echo -e "$service_name was restarted after being down for 10 minutes on $ENV" | \
                    mail -s "🔁 $service_name Restarted 🔁" "$EMAIL"

                # Reset DOWN_SINCE to avoid repeated restarts
                update_status "$down_since_var" "$current_time"
            fi
        fi
    else
        # Service has recovered
        if [ "$email_status" == "SENT" ]; then
            echo -e "$service_name has RECOVERED on $ENV" | mail -s "✅ $service_name RECOVERY Alert ✅" "$EMAIL"
        fi
        update_status "$email_status_var" "PASS"
        update_status "$down_since_var" "0"
    fi
}

# === SERVICE MONITORING CONFIG ===
check_service "SERVICE1" 4000 "tcutils"
check_service "SERVICE2" 4002 "analytics"
check_service "SERVICE3" 4003 "inventory"