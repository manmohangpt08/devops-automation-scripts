#!/usr/bin/env python3
import os
import requests
import yaml
import logging
import time

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

def load_config(path="config.yaml"):
    with open(path, "r") as f:
        return yaml.safe_load(f)

config = load_config()

JENKINS_URL = os.getenv("JENKINS_URL", config["jenkins"]["url"])
JENKINS_USER = os.getenv("JENKINS_USER", config["jenkins"]["user"])
JENKINS_TOKEN = os.getenv("JENKINS_TOKEN", config["jenkins"]["token"])
JOB_NAME = os.getenv("JOB_NAME", config["jenkins"]["job"])

def trigger_jenkins_job():
    job_url = f"{JENKINS_URL}/job/{JOB_NAME}/build"
    response = requests.post(job_url, auth=(JENKINS_USER, JENKINS_TOKEN))

    if response.status_code == 201:
        logging.info(f"Triggered Jenkins job '{JOB_NAME}' successfully!")
    else:
        logging.error(f"Failed to trigger job. Status: {response.status_code}, Response: {response.text}")

if __name__ == "__main__":
    trigger_jenkins_job()
