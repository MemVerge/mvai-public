#!/bin/bash

## Use newer kubeflow
sed -i 's/v1.7.0/v1.8.0/g' ./scripts/k8s/deploy_kubeflow.sh

## Set istio gateway to newer version
sed -i 's:istio-1-16:istio-1-17:g' ./scripts/k8s/deploy_kubeflow.sh

## Patch deploy_kubeflow with a git clone that checks for success
# cp ./git-clone.sh ./scripts/k8s/git-clone.sh
# cp ./logging.sh ./scripts/k8s/logging.sh
# sed -i '/^source /i\source git-clone.sh' ./scripts/k8s/deploy_kubeflow.sh
# sed -i 's:git clone:git_clone:g' ./scripts/k8s/deploy_kubeflow.sh

./scripts/k8s/deploy_kubeflow.sh
