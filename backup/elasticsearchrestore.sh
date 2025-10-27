#!/bin/bash

# Elasticsearch settings
ELASTICSEARCH_HOST=<ELASTICSEARCH_IP_ADDRESS>       
ELASTICSEARCH_PORT=9200              
BACKUP_DIR="/etc/elasticsearch/Backup"
aws_profile=<AWS_PROFILE>
INDEX=<ELASTICSEARCH_INDEX_NAME>
bucket_name=<BUCKET_NAME>
bucket_path=<BUCKET_PATH>

# Check for required variables and placeholder values
if [[ -z "$ELASTICSEARCH_HOST" || "$ELASTICSEARCH_HOST" == "<ELASTICSEARCH_IP_ADDRESS>" ]]; then
    echo "Error: ELASTICSEARCH_HOST is not set or contains a placeholder value."
    exit 1
fi
if [[ -z "$aws_profile" || "$aws_profile" == "<AWS_PROFILE>" ]]; then
    echo "Error: aws_profile is not set or contains a placeholder value."
    exit 1
fi
if [[ -z "$INDEX" || "$INDEX" == "<ELASTICSEARCH_INDEX_NAME>" ]]; then
    echo "Error: INDEX is not set or contains a placeholder value."
    exit 1
fi
if [[ -z "$bucket_name" || "$bucket_name" == "<BUCKET_NAME>" ]]; then
    echo "Error: bucket_name is not set or contains a placeholder value."
    exit 1
fi
if [[ -z "$bucket_path" || "$bucket_path" == "<BUCKET_PATH>" ]]; then
    echo "Error: bucket_path is not set or contains a placeholder value."
    exit 1
fi

# Check required binaries
for bin in /usr/bin/tar /usr/bin/aws /usr/bin/asbackup /usr/bin/s3cmd /usr/bin/curl; do
    if [[ ! -x "$bin" ]]; then
        echo "Error: Required binary $bin not found or not executable."
        exit 1
    fi
done

s3_ls_output=$(aws s3 ls "s3://${bucket_name}/${bucket_path}" --profile "$aws_profile")

# Parse the output to get the latest file
DATE=$(echo "$s3_ls_output" | awk '{print $4}' | sort -r | head -n 1)


cd /tmp
aws s3 cp s3://$bucket_name/$bucket_path/$DATE.tar.gz . --profile "$aws_profile"
sudo mv $DATE.tar.gz $BACKUP_DIR
sudo tar -xvf $BACKUP_DIR/$DATE.tar.gz --strip-components=3

curl -XPUT "http://$ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT/_snapshot/$DATE/backup?wait_for_completion=true" -H 'Content-Type: application/json' -d '{
    "indices": "'${INDEX}'"
}'

if [ $? -eq 0 ]; then
  echo "Elasticsearch restore completed successfully."
else
  echo "Elasticsearch restore failed."
fi