#!/usr/bin/env python3
import boto3
import os
import yaml
import logging
from datetime import datetime, timezone, timedelta

# --- Logging setup ---
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

# --- Load configuration ---
def load_config(path="config.yaml"):
    with open(path, "r") as f:
        return yaml.safe_load(f)

config = load_config()

# --- AWS Setup ---
session = boto3.Session(
    aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID", config["aws"]["access_key"]),
    aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY", config["aws"]["secret_key"]),
    region_name=os.getenv("AWS_REGION", config["aws"]["region"]),
)
ec2 = session.client("ec2")

# --- Cleanup Logic ---
def cleanup_old_instances(days_old=7):
    cutoff_date = datetime.now(timezone.utc) - timedelta(days=days_old)
    logging.info(f"Cleaning up instances older than {days_old} days...")

    instances = ec2.describe_instances(Filters=[{"Name": "instance-state-name", "Values": ["running", "stopped"]}])

    for reservation in instances["Reservations"]:
        for instance in reservation["Instances"]:
            launch_time = instance["LaunchTime"]
            instance_id = instance["InstanceId"]

            if launch_time < cutoff_date:
                logging.info(f"Terminating instance {instance_id}, launched on {launch_time}")
                ec2.terminate_instances(InstanceIds=[instance_id])

if __name__ == "__main__":
    cleanup_old_instances(config["cleanup"]["days_old"])
