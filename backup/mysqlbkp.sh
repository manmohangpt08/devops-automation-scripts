#!/bin/bash

COMMENT=${1}
if test -z "${COMMENT}"
then
        COMMENT=default
fi

# === CONFIGURATION ===
SYSTEM_USERNAME="opc"
DATABASE1="<DATABASE1_NAME>"
DATABASE2="<DATABASE2_NAME>"
S3_PROFILE="<S3_PROFILE>"
S3CFG="/home/${SYSTEM_USERNAME}/.s3cfg_<S3_PROFILE>"
S3BASE="<S3_PATH>"
MYSQL_USER="<USERNAME>"
MYSQL_PASS="<PASSWORD>"
BACKUPDIR="/home/${SYSTEM_USERNAME}/mysqlbkp/bkpdir"
DATE=$(date +%d-%m-%Y)
HOUR=$(date +%H)
NOW=$(date +%s)
S3CMD="/usr/bin/s3cmd"
LOGFILE="/home/${SYSTEM_USERNAME}/mysqlbkp/mysqlbkpcron.log"

mkdir -p /home/${SYSTEM_USERNAME}/mysqlbkp/bkpdir /home/${SYSTEM_USERNAME}/mysqlbkp/
[ -x /usr/bin/s3cmd ] || { echo "Error: /usr/bin/s3cmd not found or not executable."; exit 1; }; [ -x /usr/bin/aws ] || { echo "Error: /usr/bin/aws not found or not executable."; exit 1; }; [ -x /usr/bin/tar ] || { echo "Error: /usr/bin/tar not found or not executable."; exit 1; }

([ -z "${MYSQL_USER}" ] || [ "${MYSQL_USER}" = "<USERNAME>" ]) && echo "Please provide MYSQL_USER"; ([ -z "${MYSQL_PASS}" ] || [ "${MYSQL_PASS}" = "<PASSWORD>" ]) && echo "Please provide MYSQL_PASS"; ([ -z "${S3BASE}" ] || [ "${S3BASE}" = "<S3_PATH>" ]) && echo "Please provide S3BASE"; ([ -z "${DATABASE1}" ] || [ "${DATABASE1}" = "<DATABASE1_NAME>" ]) && echo "Please provide DATABASE1"; ([ -z "${DATABASE2}" ] || [ "${DATABASE2}" = "<DATABASE2_NAME>" ]) && echo "Please provide DATABASE2" && exit 1


# Retention in days
RETENTION_HOURLY=4     # Retain last 3 days of hourly backups
RETENTION_DAILY=30     # Retain last 30 days of daily backups
# Convert to seconds
RETENTION_HOURLY_SEC=$((RETENTION_HOURLY * 86400))
RETENTION_DAILY_SEC=$((RETENTION_DAILY * 86400))

# === DETERMINE BACKUP TYPE ===
if [ "$HOUR" == "23" ]; then
    BACKUP_TYPE="daily"
    SUFFIX="${DATE}"
else
    BACKUP_TYPE="hourly"
    SUFFIX="${DATE}_${HOUR}"
fi

# === RESET BACKUP DIR TO KEEP ONLY LATEST HOURLY FILE ===
rm -rf "$BACKUPDIR"/*
mkdir -p "$BACKUPDIR"

# === FUNCTION TO DUMP, PACKAGE, UPLOAD ===
backup_database() {
  DB_NAME="$1"
  SQL_FILE="${BACKUPDIR}/${DB_NAME}.sql"
  TGZ_FILE="${BACKUPDIR}/${DB_NAME}_${COMMENT}_${SUFFIX}.tgz"

  # Dump database to SQL file
  mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASS" "$DB_NAME" > "$SQL_FILE"

  # Create tar.gz archive
  tar -zcvf "$TGZ_FILE" -C "$BACKUPDIR" "$(basename "$SQL_FILE")"

  # Upload to S3 in the correct folder (hourly/daily)
  aws s3 cp "$TGZ_FILE" "${S3BASE}/${BACKUP_TYPE}/" --profile "$S3_PROFILE"

  # Remove local files (to keep only last hour)
  rm -f "$SQL_FILE" "$TGZ_FILE"
}


# === FUNCTION TO Backup file Cleanup ===
cleanup_backup() {
    BACKUP_TYPE=$1            # hourly or daily
    RETENTION_SEC=$2

    echo "== Checking $BACKUP_TYPE backups older than $((RETENTION_SEC / 86400)) days =="

    $S3CMD --config="$S3CFG" ls "${S3BASE}/${BACKUP_TYPE}/" | \
    grep -E '[0-9]{2}-[0-9]{2}-[0-9]{4}(_[0-9]{2})?\.tgz$' | \
    awk -v retention="$RETENTION_SEC" '
    {
    file_path = $NF
    n = split(file_path, parts, "/")
    file = parts[n]
    gsub(".tgz", "", file)

    if (match(file, /([0-9]{2}-[0-9]{2}-[0-9]{4})(_[0-9]{2})?$/, m)) {
        dt = m[1]
        hr = (length(m[2]) > 0 ? substr(m[2], 2) : "00")

        split(dt, dmy, "-")
        timestamp = sprintf("%s-%s-%s %02d:00:00", dmy[3], dmy[2], dmy[1], hr)

        cmd = "date -d \"" timestamp "\" +%s"
        cmd | getline file_time
        close(cmd)

        now = systime()
        age = now - file_time
        
        # Convert retention time to days and compare
        age_days = int(age / 86400)
        retention_days = int(retention / 86400)

        if (age > retention) {
            print file_path
        }
        
        # Handle daily retention
        if (age_days > retention_days) {
            print file_path
        }
    }
}' | while read oldfile; do
        echo "Deleting $oldfile ..." >> ${LOGFILE}
        $S3CMD --config="$S3CFG" del "$oldfile"
    done
}

# === BACKUP BOTH DATABASES ===
backup_database "${DATABASE1}"
backup_database "${DATABASE2}"

# Cleanup hourly and daily backups
if [ "$HOUR" == "23" ]; then
  cleanup_backup "daily" "$RETENTION_DAILY_SEC"
else
  cleanup_backup "hourly" "$RETENTION_HOURLY_SEC"
fi