#!/bin/bash

source venv.sh

RELEASE_NAMESPACE='mmcai-system'
MMCLOUD_OPERATOR_NAMESPACE='mmcloud-operator-system'
PROMETHEUS_NAMESPACE='monitoring'

CERT_MANAGER_VERSION='v1.15.3'
KUBEFLOW_VERSION='v1.9.0'
NVIDIA_GPU_OPERATOR_VERSION='v24.3.0'

ANSIBLE_VENV='mmai-ansible'
ANSIBLE_INVENTORY_DATABASE_NODE_GROUP='mmai-database'

TEMP_DIR=$(mktemp -d)

cleanup() {
    dvenv || true
    rm -rf $TEMP_DIR
    exit
}

trap cleanup EXIT

cvenv $ANSIBLE_VENV || true
avenv $ANSIBLE_VENV
pip install -q ansible
