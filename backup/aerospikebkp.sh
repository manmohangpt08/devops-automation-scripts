#!/bin/bash

# System username variable
SYSTEM_USERNAME="opc"

# Aerospike backup settings
AS_HOST="localhost"
AS_PORT=3000
BACKUP_DIR="/home/${SYSTEM_USERNAME}/aerospike/backup"
NAMESPACE=<NAMESPACE>  # <-- Set your namespace here
aws_profile=<AWS_PROFILE>   # <-- Set your AWS profile here
bucket_name=<BUCKET_NAME> # <-- Set your bucket name here
bucket_path=<BUCKET_PATH>    # <-- Set your bucket path here
TIMESTAMP=$(date +"%Y%m%d%H%M%S")

# Check NAMESPACE
if [[ -z "$NAMESPACE" || "$NAMESPACE" == "<NAMESPACE>" ]]; then
    echo "Error: NAMESPACE is not set. Please set the NAMESPACE variable."
    exit 1
fi

# Check AWS variables
if [[ -z "$aws_profile" || "$aws_profile" == "<AWS_PROFILE>" ]]; then
    echo "Error: aws_profile is not set. Please set the aws_profile variable."
    exit 1
fi
if [[ -z "$bucket_name" || "$bucket_name" == "<BUCKET_NAME>" ]]; then
    echo "Error: bucket_name is not set. Please set the bucket_name variable."
    exit 1
fi
if [[ -z "$bucket_path" || "$bucket_path" == "<BUCKET_PATH>" ]]; then
    echo "Error: bucket_path is not set. Please set the bucket_path variable."
    exit 1
fi

# Check required binaries
for bin in /usr/bin/tar /usr/bin/aws /usr/bin/asbackup /usr/bin/s3cmd; do
    if [[ ! -x "$bin" ]]; then
        echo "Error: Required binary $bin not found or not executable."
        exit 1
    fi
done

# Ensure backup directory exists
if [[ ! -d "$BACKUP_DIR" ]]; then
    mkdir -p "$BACKUP_DIR"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create backup directory $BACKUP_DIR"
        exit 1
    fi
fi

# Run asbackup command to create a backup
asbackup --host $AS_HOST --port $AS_PORT --namespace "$NAMESPACE" --directory "$BACKUP_DIR/$TIMESTAMP"

cd $BACKUP_DIR
tar -zvcf $TIMESTAMP.tar.gz $TIMESTAMP
aws s3 cp $TIMESTAMP.tar.gz s3://$bucket_name/$bucket_path/ --profile "$aws_profile"
rm $TIMESTAMP.tar.gz

# Remove the files from s3 older than 30 days
s3cmd --config=/home/${SYSTEM_USERNAME}/.s3cfg_${aws_profile} ls s3://$bucket_name/$bucket_path/ | while read -r line;
    do
        createDate=$(echo $line | awk '{print $1" "$2}')
        createDate=$(date -d"$createDate" +%s)
        olderThan=$(date -d"-30 days" +%s)
        if [[ $createDate -lt $olderThan ]]; then
            fileName=$(echo $line | awk '{print $4}')
            if [[ $fileName != "" ]]; then
                s3cmd --config=/home/${SYSTEM_USERNAME}/.s3cfg_${aws_profile} del "$fileName"
            fi
        fi
done

# Check the exit status of asbackup
if [ $? -eq 0 ]; then
    echo "Aerospike backup completed successfully."
else
    echo "Aerospike backup failed."
fi