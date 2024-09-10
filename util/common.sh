#!/bin/bash

set -euo pipefail

curl -LfsSo logging.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/util/logging.sh
curl -LfsSo venv.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/util/venv.sh

source logging.sh
source venv.sh

RELEASE_NAMESPACE='mmcai-system'
MMCLOUD_OPERATOR_NAMESPACE='mmcloud-operator-system'
PROMETHEUS_NAMESPACE='monitoring'

CERT_MANAGER_VERSION='v1.15.3'
KUBEFLOW_VERSION='v1.9.0'
KUBEFLOW_ISTIO_VERSION='1.22'
NVIDIA_GPU_OPERATOR_VERSION='v24.3.0'

ANSIBLE_VENV='mmai-ansible'
ANSIBLE_INVENTORY_DATABASE_NODE_GROUP='mmai_database'

KUBEFLOW_MANIFEST='kubeflow-manifest.yaml'

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

build_kubeflow() {
    log "Cloning Kubeflow manifests..."
    git clone https://github.com/kubeflow/manifests.git $TEMP_DIR/kubeflow --branch $KUBEFLOW_VERSION

    # From DeepOps: Change the default Istio Ingress Gateway configuration to support NodePort for ease-of-use in on-prem
    path_istio_version=${KUBEFLOW_ISTIO_VERSION#v}
    path_istio_version=${path_istio_version//./-}
    sed -i 's:ClusterIP:NodePort:g' "$TEMP_DIR/kubeflow/common/istio-$path_istio_version/istio-install/base/patches/service.yaml"

    # From DeepOps: Make the Kubeflow cluster allow insecure http instead of https
    # https://github.com/kubeflow/manifests#connect-to-your-kubeflow-cluster
    sed -i 's:JWA_APP_SECURE_COOKIES=true:JWA_APP_SECURE_COOKIES=false:' "$TEMP_DIR/kubeflow/apps/jupyter/jupyter-web-app/upstream/base/params.env"
    sed -i 's:VWA_APP_SECURE_COOKIES=true:VWA_APP_SECURE_COOKIES=false:' "$TEMP_DIR/kubeflow/apps/volumes-web-app/upstream/base/params.env"
    sed -i 's:TWA_APP_SECURE_COOKIES=true:TWA_APP_SECURE_COOKIES=false:' "$TEMP_DIR/kubeflow/apps/tensorboard/tensorboards-web-app/upstream/base/params.env"

    kustomize build $TEMP_DIR/kubeflow/example > $TEMP_DIR/$KUBEFLOW_MANIFEST
}
