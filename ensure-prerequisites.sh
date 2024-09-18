#!/bin/bash

set -euo pipefail

imports='
    logging.sh
    venv.sh
'
for import in $imports; do
    if ! curl -LfsSo $import https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/unified-setup/util/$import; then
        echo "Error getting script dependency: $import"
        exit 1
    fi
    source $import
done

OS=windows
if [[ "$OSTYPE" == linux* ]]; then
  OS=linux
elif [[ "$OSTYPE" == darwin* ]]; then
  OS=darwin
fi
echo "Operating system: $OS"

if [[ "$OS" == windows ]]; then
    log_bad "OS not supported. Please install prerequisites manually."
    exit 1
fi

ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64";;
    x86|i686|i386) ARCH="386";;
    aarch64) ARCH="arm64";;
esac
echo "Architecture: $ARCH"

INSTALL_DIR="/usr/local/bin"

KUBECTL="$INSTALL_DIR/kubectl"
KUSTOMIZE="$INSTALL_DIR/kustomize"
HELM="$INSTALL_DIR/helm"
JQ="$INSTALL_DIR/jq"
YQ="$INSTALL_DIR/yq"

KUSTOMIZE_MIN_VERSION="v5.4.3"
HELM_MIN_VERSION="v3.15.4"
JQ_MIN_VERSION="jq-1.7.1"
YQ_MIN_VERSION="v4.44.3"

version_le() {
    echo -e "$1\n$2" | sort --version-sort -C
}

move_file_to_save_if_file_present() {
    local file_path="$1"
    local save_path="$(dirname "$file_path")/mmai-save.$(basename "$file_path")"
    if [[ -e $file_path ]]; then
        sudo mv "$file_path" "$save_path"
        log "Moved $file_path to $save_path"
    fi
}

move_file_from_save_if_save_present() {
    local file_path="$1"
    local save_path="$(dirname "$file_path")/mmai-save.$(basename "$file_path")"
    if [[ -e $save_path ]]; then
        sudo mv "$save_path" "$file_path"
        log "Moved $save_path to $file_path"
    fi
}

div
if cvenv mmai-test-venv; then
    rvenv mmai-test-venv
    log "venv creation works."
else
    rvenv mmai-test-venv || true
    log_bad "venv creation failed. Please fix before continuing."
    exit 1
fi

div
if [[ -f "$KUBECTL" ]]; then
    log "Found kubectl. Skipping kubectl installation."
else
    KUBECTL_INSTALL_VERSION="$(curl -Lfs https://dl.k8s.io/release/stable.txt)"
    log_good "Installing kubectl $KUBECTL_INSTALL_VERSION..."
    sudo curl -Lfo "$KUBECTL" "https://dl.k8s.io/release/${KUBECTL_INSTALL_VERSION}/bin/${OS}/${ARCH}/kubectl"
    sudo chmod +x "$KUBECTL"
    echo "kubectl installed to $KUBECTL"
fi

div
if [[ -f "$KUSTOMIZE" ]] && version_le "$KUSTOMIZE_MIN_VERSION" "$("$KUSTOMIZE" version)"; then
    log "Found Kustomize >= $KUSTOMIZE_MIN_VERSION. Skipping Kustomize installation."
else
    log_good "Installing latest Kustomize..."
    move_file_to_save_if_file_present "$KUSTOMIZE"
    if ! curl -Lf "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | sudo bash -s -- $INSTALL_DIR; then
        log_bad "Error installing latest Kustomize."
        move_file_from_save_if_save_present "$KUSTOMIZE"
        exit 1
    fi
fi

div
if [[ -f "$HELM" ]] && version_le "$HELM_MIN_VERSION" "$("$HELM" version --template '{{.Version}}')"; then
    log "Found Helm >= $HELM_MIN_VERSION. Skipping Helm installation."
else
    log_good "Installing latest Helm..."
    move_file_to_save_if_file_present "$HELM"
    if ! curl -Lf "https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3" | bash; then
        log_bad "Error installing latest Helm."
        move_file_from_save_if_save_present "$HELM"
        exit 1
    fi
fi

div
if [[ -f "$JQ" ]] && version_le "$JQ_MIN_VERSION" "$("$JQ" --version)"; then
    log "Found jq >= $JQ_MIN_VERSION. Skipping jq installation."
else
    JQ_OS=$OS
    if [[ "$JQ_OS" == "darwin" ]]; then
      JQ_OS=macos
    fi

    JQ_ARCH=$ARCH
    if [[ "$JQ_ARCH" == "386" ]]; then
      JQ_ARCH="i386"
    fi

    log_good "Installing latest jq..."
    move_file_to_save_if_file_present "$JQ"
    if ! sudo curl -Lfo "$JQ" "https://github.com/jqlang/jq/releases/latest/download/jq-${JQ_OS}-${JQ_ARCH}"; then
        log_bad "Error installing latest jq."
        move_file_from_save_if_save_present "$JQ"
        exit 1
    fi
    sudo chmod +x "$JQ"
    echo "jq installed to $JQ"
fi

div
if [[ -f "$YQ" ]] && version_le "$YQ_MIN_VERSION" "$("$YQ" --version | awk '{print $4}')"; then
    log "Found yq >= $YQ_MIN_VERSION. Skipping yq installation."
else
    log_good "Installing latest yq..."
    move_file_to_save_if_file_present "$YQ"
    if ! sudo curl -Lfo $YQ "https://github.com/mikefarah/yq/releases/latest/download/yq_${OS}_${ARCH}"; then
        log_bad "Error installing latest yq."
        move_file_from_save_if_save_present "$YQ"
        exit 1
    fi
    sudo chmod +x "$YQ"
    echo "yq installed to $YQ"
fi
