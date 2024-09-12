#!/bin/bash

source logging.sh

TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf $TEMP_DIR
    exit
}

trap cleanup EXIT

div
log "Performing kubeflow teardown."
log "First, installing kustomize..."
div

wget -O install_kustomize.sh "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"
chmod +x install_kustomize.sh
./install_kustomize.sh

sudo chmod 755 kustomize

sudo cp kustomize /usr/local/bin

rm -rf kustomize
rm -rf install_kustomize.sh

KUBEFLOW_VERSION='v1.9.0'
KUBEFLOW_ISTIO_VERSION='1.22'
KUBEFLOW_MANIFEST='kubeflow-manifest.yaml'

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

delete_kubeflow() {
    if kubectl get profiles.kubeflow.org &> /dev/null && ! kubectl delete profiles.kubeflow.org --all && kubectl get profiles.kubeflow.org; then
        return 1
    fi
    kubectl delete --ignore-not-found -f $TEMP_DIR/$KUBEFLOW_MANIFEST
}

attempts=5
log "Deleting all Kubeflow resources..."
log "Attempts remaining: $((attempts))"
while [ $attempts -gt 0 ] && ! delete_kubeflow; do
    attempts=$((attempts - 1))
    log "Kubeflow removal incomplete."
    log "Attempts remaining: $((attempts))"
    log "Waiting 15 seconds before attempt..."
    sleep 15
done
log "Kubeflow should be removed."

div
log "Check if there are any remaining kubeflow pods or namespaces."
div
