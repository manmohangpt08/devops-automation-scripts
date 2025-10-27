#!/bin/bash

# Elasticsearch settings
SYSTEM_USERNAME=opc
ELASTICSEARCH_HOST=<IP_ADDRESS>       
ELASTICSEARCH_PORT=9200              
BACKUP_DIR="/etc/elasticsearch/Backup"        
DATE=$(date +'%d%b%Y')
INDEX="_all"
aws_profile=<AWS_PROFILE>
bucket_name=<BUCKET_NAME>
bucket_path=<BUCKET_PATH>

sudo mkdir $BACKUP_DIR/$DATE
sudo chown elasticsearch:elasticsearch $BACKUP_DIR/$DATE

# Check required binaries
for bin in /usr/bin/tar /usr/bin/aws /usr/bin/asbackup /usr/bin/s3cmd /usr/bin/curl; do
    if [[ ! -x "$bin" ]]; then
        echo "Error: Required binary $bin not found or not executable."
        exit 1
    fi
done

#Make a folder for Backup:
curl -XPUT "http://$ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT/_snapshot/$DATE" -H 'Content-Type: application/json' -d '{
    "type": "fs",
    "settings": {
        "location": "'${DATE}'",
        "compress": "true"
    }
}'
#Take Backup:
curl -XPUT "http://$ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT/_snapshot/$DATE/backup?wait_for_completion=true" -H 'Content-Type: application/json' -d '{
    "indices": "'${INDEX}'",
    "ignore_unavailable": true,
    "include_global_state": false
}'

sudo tar -zvcf /home/${SYSTEM_USERNAME}/elasticsearch/backup/$DATE.tar.gz $BACKUP_DIR/$DATE
aws s3 cp /home/${SYSTEM_USERNAME}/elasticsearch/backup/$DATE.tar.gz s3://$bucket_name/$bucket_path/ --profile "$aws_profile"
sudo rm /home/${SYSTEM_USERNAME}/elasticsearch/backup/$DATE.tar.gz

#remove the files from s3
s3cmd --config=/home/${SYSTEM_USERNAME}/.s3cfg_${aws_profile} ls s3://$bucket_name/$bucket_path/ | while read -r line;
  do
    createDate=`echo $line|awk {'print $1" "$2'}`
    createDate=`date -d"$createDate" +%s`
    olderThan=`date -d"-30 days" +%s`
    if [[ $createDate -lt $olderThan ]]
      then
	fileName=`echo $line|awk {'print $4'}`
        if [[ $fileName != "" ]]
          then
            s3cmd --config=/home/${SYSTEM_USERNAME}/.s3cfg_${aws_profile} del "$fileName"
        fi
    fi
done;

if [ $? -eq 0 ]; then
  echo "Elasticsearch backup completed successfully."
else
  echo "Elasticsearch backup failed."
fi