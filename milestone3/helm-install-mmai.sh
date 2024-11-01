#!/bin/bash

echo "should be run within mmai/"

# Define local registry URL and port
REGISTRY_URL="localhost:5000"

# Install cert-manager:
# Add the Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io

# Update your local Helm chart repository cache
helm repo update

# Install the cert-manager Helm chart
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

# Install the prometheus operator helm chart
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack

AWS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
AWS_HOSTNAME=$(curl -H "X-aws-ec2-metadata-token: $AWS_TOKEN" "http://169.254.169.254/latest/meta-data/public-hostname")
MMAI_NAMESPACE="mmai-system"

# Create mmai-system ns
kubectl create namespace $MMAI_NAMESPACE

# Check if dist/ directory exists and install .tgz charts with Helm
if [[ -d "dist" ]]; then
    echo "Installing Helm charts from dist/ directory..."

    mmai_chart=$(ls dist/mmai-*.*.*-* | head -n 1)
    mmai_ctrl_chart=$(ls dist/mmai-ctrl-*.*.*-* | head -n 1)

    fullname_override="mmai"
    chart="$mmai_chart"
    helm install -v2 "$fullname_override" "$chart" \
    --namespace $MMAI_NAMESPACE \
    --set image.repository="$REGISTRY_URL/mmai" \
    --set fullnameOverride="$fullname_override" \
    --set hostname=$AWS_HOSTNAME \
    --set bootstrapPassword=admin

    fullname_override="mmai-ctrl"
    chart="$mmai_ctrl_chart"
    helm install -v8 "$fullname_override" "$chart" \
    --namespace $MMAI_NAMESPACE \
    --set image.repository="$REGISTRY_URL/mmai-ctrl" \
    --set kueue.controllerManager.image.repository="$REGISTRY_URL/kueue" \
    --set kueue.managerConfig.namespace="$MMAI_NAMESPACE" \
    --set fullnameOverride="$fullname_override"
else
    echo "No dist/ directory found. Skipping Helm installation."
fi

# If things go wrong:
# Uninstall all kueue CRDS
# kubectl get crds | grep "kueue.x-k8s" | awk '{print $1}' | xargs -I {} kubectl delete crd {}
# Uninstall engines.mmcloud.io
# kubectl delete crd engines.mmcloud.io
# Uninstall mmai crds
# kubectl get crds | grep "mmai" | awk '{print $1}' | xargs -I {} kubectl delete crd {}
