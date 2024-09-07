#!/bin/bash

RELEASE_NAMESPACE='mmcai-system'
MMCLOUD_OPERATOR_NAMESPACE='mmcloud-operator-system'
PROMETHEUS_NAMESPACE='monitoring'

CERT_MANAGER_VERSION='v1.15.3'
KUBEFLOW_VERSION='v1.8.1'
NVIDIA_GPU_OPERATOR_VERSION='v24.3.0'

PYTHON=$(which python3 || which python)

ANSIBLE_VENV='mmai-ansible'
ANSIBLE_INVENTORY_DATABASE_NODE_GROUP='mmai_database'

TEMP_DIR=$(mktemp -d)
VENV_DIR=".mmai-venvs"

cvenv() {
  if (( $# == 1 )); then
    venvpath=$VENV_DIR/$1
    if [[ ! -d $venvpath && ! -f $venvpath ]]; then
      $PYTHON -m venv $venvpath
    else
      echo "Cannot create venv: name already exists"
      return 1
    fi
  else
    echo "Cannot create venv: 1 argument expected, $# received"
    return 1
  fi
}

avenv() {
  if (( $# == 1 )); then
    activatevenvpath=$VENV_DIR/$1/bin/activate
    if [[ -f $activatevenvpath ]]; then
      source $activatevenvpath
    else
      echo "Cannot activate venv: venv does not exist"
      return 1
    fi
  else
    echo "Cannot activate venv: 1 argument expected, $# received"
    return 1
  fi
}

lvenv() {
  ls $VENV_DIR
}

dvenv() {
  deactivate
}

rvenv() {
  if (( $# == 1 )); then
    venvpath=$VENV_DIR/$1
    if [[ -d $venvpath ]]; then
      rm -rf $venvpath
    else
      echo "Cannot remove venv: venv does not exist"
      return 1
    fi
  else
    echo "Cannot remove venv: 1 argument expected, $# received"
    return 1
  fi
}

cleanup() {
    dvenv || true
    rm -rf $TEMP_DIR
    exit
}

trap cleanup EXIT

cvenv $ANSIBLE_VENV || true
avenv $ANSIBLE_VENV
pip install -q ansible
