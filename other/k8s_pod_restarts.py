#!/usr/bin/env python3
"""
Example Usage: export KUBECONFIG=~/.kube/config && export RESTART_THRESHOLD=3 && python3 k8s_pod_restarts.py
"""

from kubernetes import client, config
import os
import logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

def main():
    kubeconfig = os.getenv("KUBECONFIG", "~/.kube/config")
    config.load_kube_config(kubeconfig)

    v1 = client.CoreV1Api()
    namespaces = [ns.metadata.name for ns in v1.list_namespace().items]

    restart_threshold = int(os.getenv("RESTART_THRESHOLD", 5))

    for ns in namespaces:
        pods = v1.list_namespaced_pod(ns).items
        for pod in pods:
            total_restarts = sum([c.restart_count for c in pod.status.container_statuses or []])
            if total_restarts >= restart_threshold:
                logging.warning(f"Pod {pod.metadata.name} in {ns} restarted {total_restarts} times.")

if __name__ == "__main__":
    main()
