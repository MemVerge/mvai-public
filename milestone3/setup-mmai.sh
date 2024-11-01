#!/bin/bash

# Function to compare versions
version_check() {
    # Compare two version numbers, e.g., "10.9.0" vs. "10.8.0"
    if [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" == "$2" ]; then
        return 0  # version is adequate
    else
        return 1  # version is not adequate
    fi
}

# Check for npm version >= 10.9.0
if command -v npm &> /dev/null; then
    npm_version=$(npm -v)
    if ! version_check "$npm_version" "10.9.0"; then
        echo "npm version must be >= 10.9.0. Found: $npm_version. Exiting."
        exit 1
    fi
else
    echo "npm is not installed. Exiting."
    exit 1
fi

# Check for node version >= v22.11.0
if command -v node &> /dev/null; then
    node_version=$(node -v | sed 's/v//')  # Strip the 'v' prefix from version
    if ! version_check "$node_version" "22.11.0"; then
        echo "node version must be >= v22.11.0. Found: v$node_version. Exiting."
        exit 1
    fi
else
    echo "node is not installed. Exiting."
    exit 1
fi

# Check for docker
if ! command -v docker &> /dev/null; then
    echo "docker is not installed. Exiting."
    exit 1
fi

# Check for build-essential
if ! dpkg -s build-essential &> /dev/null; then
    echo "build-essential package is not installed. Exiting."
    exit 1
fi

# Prompt to set up k3s
read -p "Do you want to set up k3s? (y/n): " setup_k3s
if [[ "$setup_k3s" == "y" ]]; then
    curl -sfL https://get.k3s.io | sh -
    sudo chmod 776 /etc/rancher/k3s/k3s.yaml
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> ~/.bashrc

    echo "Please run `source ~/.bashrc to enable kubectl`"
fi

# Prompt to install Helm
read -p "Do you want to install Helm? (y/n): " install_helm
if [[ "$install_helm" == "y" ]]; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Prompt to build mmai
read -p "Do you want to build mmai? As part of this process, you will need to provide GitHub credentials for logging in to ghcr.io/memverge/charts. (y/n): " build_mmai
if [[ "$build_mmai" == "y" ]]; then
    git clone https://github.com/MemVerge/mmai.git
    cd mmai || exit
    git checkout milestone3
    git submodule update --init --recursive
    go mod tidy
    make vendor
    make docker-build
    # Login to helm, which is needed to pull dependency charts for mmai
    helm registry login ghcr.io/memverge/charts
    make helm-build
    cd ..
fi