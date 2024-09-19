#!/bin/bash

set -uo pipefail

ignore_errors=false

while getopts "i" option; do
    case $option in
        i ) ignore_errors=true;;
        * ) echo "Invalid option. Use -i to ignore errors."
    esac
done

if ! $ignore_errors; then
    set -e
fi

imports='
    common.sh
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

MMAI_SETUP_LOG_DIR="mmai-setup-$(file_timestamp)"
mkdir -p $MMAI_SETUP_LOG_DIR
LOG_FILE="$MMAI_SETUP_LOG_DIR/mmai-setup.log"
set_log_file $LOG_FILE

ensure_prerequisites

log_good "Script dependencies satisfied."

TEMP_DIR=$(mktemp -d)
cleanup() {
    dvenv || true
    rm -rf $TEMP_DIR
}
trap cleanup EXIT

cvenv $ANSIBLE_VENV || true
avenv $ANSIBLE_VENV
pip install -q ansible

log_good "venv $ANSIBLE_VENV set up."

################################################################################

install_mmcai_manager=false
install_mmcai_cluster=false
install_nvidia_gpu_operator=false
install_kubeflow=false
install_cert_manager=false # Allow instead of kubeflow if not installing mmcai-manager.

confirm_selection=false

# Sanity check.
log "Getting Kubernetes version to check connectivity."
if ! "$KUBECTL" version; then
    log_bad "Error getting version. Cannot proceed with setup."
    exit 1
else
    log_good "Got version successfully. Proceeding with setup."
fi

helm_login() {
    # Extract creds.
    local secret_json=$(
        "$KUBECTL" get secret memverge-dockerconfig -n $RELEASE_NAMESPACE --output="jsonpath={.data.\.dockerconfigjson}" |
        base64 --decode
    )
    local secret_user=$(echo ${secret_json} | "$JQ" -r '.auths."ghcr.io/memverge".username')
    local secret_token=$(echo ${secret_json} | "$JQ" -r '.auths."ghcr.io/memverge".password')

    # Attempt login.
    if echo $secret_token | "$HELM" registry login ghcr.io/memverge -u $secret_user --password-stdin; then
        log_good "Helm login was successful."
    else
        log_bad "Helm login was unsuccessful."
        echo "Please provide an mmcai-ghcr-secret.yaml that allows Helm login."
        div
        log "Content:"
        cat mmcai-ghcr-secret.yaml
        div
        exit 1
    fi
}

if [[ -f "mmcai-ghcr-secret.yaml" ]]; then
    div
    "$KUBECTL" apply -f mmcai-ghcr-secret.yaml
    "$HELM" registry logout ghcr.io/memverge
    helm_login
    div
fi

if "$KUBECTL" get secret -n $RELEASE_NAMESPACE memverge-dockerconfig; then
    release_namespace_image_pull_secrets_detected=true
else
    release_namespace_image_pull_secrets_detected=false
    log_bad "MemVerge image pull secret in namespace $RELEASE_NAMESPACE not detected."
fi

if "$KUBECTL" get secret -n $MMCLOUD_OPERATOR_NAMESPACE memverge-dockerconfig; then
    mmcloud_operator_namespace_image_pull_secrets_detected=true
else
    mmcloud_operator_namespace_image_pull_secrets_detected=false
    log_bad "MemVerge image pull secret in namespace $MMCLOUD_OPERATOR_NAMESPACE not detected."
fi

if ! $release_namespace_image_pull_secrets_detected \
|| ! $mmcloud_operator_namespace_image_pull_secrets_detected
then
    log_bad "Cannot proceed with setup."
    exit 1
fi

# Determine if cert-manager is installed.
cert_manager_detected() {
    "$KUBECTL" get namespace cert-manager
}
if ! cert_manager_detected; then
    log "cert-manager not detected."
fi

# Determine if Kubeflow is installed.
kubeflow_detected() {
    "$KUBECTL" get namespace kubeflow
}
if ! kubeflow_detected; then
    log "Kubeflow not detected."
fi

# Determine if nvidia-gpu-operator is installed.
nvidia_gpu_operator_detected() {
    "$HELM" list -n gpu-operator -a -q | grep gpu-operator
}
if ! nvidia_gpu_operator_detected; then
    log "NVIDIA GPU Operator not detected."
fi

# Determine if mmcai-cluster is installed.
mmcai_cluster_detected() {
    "$HELM" list -n mmcai-system -a -q | grep mmcai-cluster
}
if ! mmcai_cluster_detected; then
    log "MMC.AI Cluster not detected."
fi

# Determine if mmcai-manager is installed.
mmcai_manager_detected() {
    "$HELM" list -n mmcai-system -a -q | grep mmcai-manager
}
if ! mmcai_manager_detected; then
    log "MMC.AI Manager not detected."
fi

################################################################################

# Install mmcai-manager?
if ! mmcai_manager_detected; then
    div
    if input_default_yn "Install MMC.AI Manager [y/N]:" n; then
        install_mmcai_manager=true
    else
        install_mmcai_manager=false
    fi
fi

if $install_mmcai_manager || mmcai_manager_detected; then
    be_mmcai_manager=true
else
    be_mmcai_manager=false
fi

while $be_mmcai_manager && cert_manager_detected && ! kubeflow_detected; do
    echo "MMC.AI Manager requires Kubeflow, which provides cert-manager. Please uninstall existing cert-manager before continuing if you wish to install MMC.AI Manager."
    if input_default_yn "Continue setup [Y/n]:" y; then
        continue_setup=true
    else
        continue_setup=false
    fi
    if ! $continue_setup; then
        exit 0
    fi

    log "Continuing setup..."
    if ! cert_manager_detected; then
        log "cert-manager not detected."
    fi
    if ! kubeflow_detected; then
        log "Kubeflow not detected."
    fi
done

# Install mmcai-cluster?
if ! mmcai_cluster_detected; then
    if $be_mmcai_manager; then
        echo "MMC.AI Manager does not work without MMC.AI Cluster. MMC.AI Cluster will be installed."
        install_mmcai_cluster=true
    else
        div
        if input_default_yn "Install MMC.AI Cluster [y/N]:" n; then
            install_mmcai_cluster=true
        else
            install_mmcai_cluster=false
        fi
    fi
fi

if $install_mmcai_cluster || mmcai_cluster_detected; then
    be_mmcai_cluster=true
else
    be_mmcai_cluster=false
fi

if $install_mmcai_cluster && nvidia_gpu_operator_detected; then
    echo "MMC.AI Cluster requires NVIDIA GPU Operator installed with a specific configuration. If existing NVIDIA GPU Operator was not installed using this script, please uninstall existing NVIDIA GPU Operator before continuing."
    if input_default_yn "Continue setup [Y/n]:" y; then
        continue_setup=true
    else
        continue_setup=false
    fi
    if ! $continue_setup; then
        exit 0
    fi

    log "Continuing setup..."
    if ! nvidia_gpu_operator_detected; then
        log "NVIDIA GPU Operator not detected."
    fi
fi

# Install NVIDIA GPU Operator?
if ! nvidia_gpu_operator_detected; then
    if $be_mmcai_cluster; then
        echo "NVIDIA GPU Operator is required by MMC.AI Cluster. NVIDIA GPU Operator will be installed."
        install_nvidia_gpu_operator=true
    else
        div
        if input_default_yn "Install NVIDIA GPU Operator [y/N]:" n; then
            install_nvidia_gpu_operator=true
        else
            install_nvidia_gpu_operator=false
        fi
    fi
fi

if $install_mmcai_manager && kubeflow_detected; then
    echo "MMC.AI Manager requires Kubeflow installed with a specific configuration. If existing Kubeflow was not installed using this script, please uninstall existing Kubeflow before continuing."
    if input_default_yn "Continue setup [Y/n]:" y; then
        continue_setup=true
    else
        continue_setup=false
    fi
    if ! $continue_setup; then
        exit 0
    fi

    log "Continuing setup..."
    if ! kubeflow_detected; then
        log "Kubeflow not detected."
    fi
fi

# Install Kubeflow?
if ! kubeflow_detected; then
    if $be_mmcai_manager; then
        echo "Kubeflow is required by MMC.AI Manager. Kubeflow will be installed."
        install_kubeflow=true
    else
        div
        if input_default_yn "Install Kubeflow [y/N]:" n; then
            install_kubeflow=true
        else
            install_kubeflow=false
        fi
    fi
fi

if $install_kubeflow || kubeflow_detected; then
    be_kubeflow=true
else
    be_kubeflow=false
fi

# Install cert-manager?
if ! $be_kubeflow && ! cert_manager_detected; then
    if $be_mmcai_cluster; then
        echo "cert-manager is required by MMC.AI Cluster. cert-manager (Helm chart) will be installed."
        install_cert_manager=true
    else
        div
        if input_default_yn "Install cert-manager (Helm chart) [y/N]:" n; then
            install_cert_manager=true
        else
            install_cert_manager=false
        fi
    fi
fi

# Get Ansible inventory for components that need it.
if $install_mmcai_cluster || $install_kubeflow; then
    ANSIBLE_INVENTORY=''
    until [[ -e "$ANSIBLE_INVENTORY" ]]; do
        echo "Provide an Ansible inventory with the following Ansible host groups:"
        if $install_kubeflow; then
            echo "- [all] (used if installing Kubeflow)"
        fi
        if $install_mmcai_cluster; then
            echo "- [$ANSIBLE_INVENTORY_DATABASE_NODE_GROUP] (used if installing MMC.AI Cluster)"
        fi
        input "Ansible inventory: " ANSIBLE_INVENTORY
        if ! [[ -e "$ANSIBLE_INVENTORY" ]]; then
            log_bad "Path does not exist."
        fi
    done

    if $install_mmcai_cluster; then
        MYSQL_NODE_HOSTNAME=$(ansible-inventory --list -i $ANSIBLE_INVENTORY | "$JQ" -r --arg NODE_GROUP "$ANSIBLE_INVENTORY_DATABASE_NODE_GROUP" '.[$NODE_GROUP].hosts[]?')
        while (( $(echo $MYSQL_NODE_HOSTNAME | wc -w) != 1 )); do
            log_bad "Wrong number of $ANSIBLE_INVENTORY_DATABASE_NODE_GROUP nodes in Ansible inventory."
            echo "Number of $ANSIBLE_INVENTORY_DATABASE_NODE_GROUP nodes must be 1. Please fix Ansible inventory before continuing."
            if input_default_yn "Continue setup [Y/n]:" y; then
                continue_setup=true
            else
                continue_setup=false
            fi
            if ! $continue_setup; then
                exit 0
            fi
            MYSQL_NODE_HOSTNAME=$(ansible-inventory --list -i $ANSIBLE_INVENTORY | "$JQ" -r --arg NODE_GROUP "$ANSIBLE_INVENTORY_DATABASE_NODE_GROUP" '.[$NODE_GROUP].hosts[]?')
        done

        if "$KUBECTL" get secret -n $RELEASE_NAMESPACE mmai-mysql-secret &>/dev/null; then
            mysql_secret_exists=true
            log "Existing billing database secret found."
        else
            mysql_secret_exists=false
        fi

        if $mysql_secret_exists; then
            echo "Reuse existing billing database secret? If N/n, the existing database secret will be overwritten."
            if input_default_yn "Reuse existing secret [Y/n]:" y; then
                create_mysql_secret=false
            else
                create_mysql_secret=true
            fi
        else
            create_mysql_secret=true
        fi

        if $create_mysql_secret; then
            echo "Enter new billing database secret."
            MYSQL_ROOT_PASSWORD=''
            MYSQL_ROOT_PASSWORD_CONFIRMATION='nonempty'
            until [[ "$MYSQL_ROOT_PASSWORD" == "$MYSQL_ROOT_PASSWORD_CONFIRMATION" ]]; do
                input_secret "Billing database root password:" MYSQL_ROOT_PASSWORD
                input_secret "Confirm database root password:" MYSQL_ROOT_PASSWORD_CONFIRMATION
                if [[ "$MYSQL_ROOT_PASSWORD" != "$MYSQL_ROOT_PASSWORD_CONFIRMATION" ]]; then
                    log_bad "Passwords do not match."
                fi
            done
        else
            log "Using existing billing database secret."
        fi
    fi
fi

################################################################################

div
echo "COMPONENT: INSTALL"
echo "MMC.AI Manager:" $install_mmcai_manager
echo "MMC.AI Cluster:" $install_mmcai_cluster
echo "NVIDIA GPU Operator:" $install_nvidia_gpu_operator
echo "Kubeflow:" $install_kubeflow
echo "cert-manager:" $install_cert_manager

div
if input_default_yn "Confirm selection [y/N]:" n; then
    confirm_selection=true
else
    confirm_selection=false
fi

if ! $confirm_selection; then
    div
    log_good "Aborting..."
    exit 0
fi

div
log_good "Beginning setup..."

################################################################################

if $install_cert_manager; then
    div
    LOG_FILE="$MMAI_SETUP_LOG_DIR/install-cert-manager.log"
    set_log_file $LOG_FILE
    log_good "Installing cert-manager..."
    "$HELM" repo add jetstack https://charts.jetstack.io
    "$HELM" repo update
    if "$HELM" install --wait --create-namespace -n cert-manager cert-manager jetstack/cert-manager --version $CERT_MANAGER_VERSION \
        --set crds.enabled=true \
        --debug
    then
        log_good "cert-manager installed."
    else
        log_bad "Error installing cert-manager."
        CERT_MANAGER_LOG_DIR="$MMAI_SETUP_LOG_DIR/cert-manager"
        mkdir $CERT_MANAGER_LOG_DIR

        CERT_MANAGER_MANIFEST="$CERT_MANAGER_LOG_DIR/manifest.yaml"
        helm_manifest -n cert-manager cert-manager jetstack/cert-manager --version $CERT_MANAGER_VERSION \
            --set crds.enabled=true \
            --include-crds \
            --debug \
            > $CERT_MANAGER_MANIFEST

        get_describe_manifest_resources $CERT_MANAGER_MANIFEST $CERT_MANAGER_LOG_DIR
    fi
fi

if $install_kubeflow; then
    div
    LOG_FILE="$MMAI_SETUP_LOG_DIR/install-kubeflow.log"
    set_log_file $LOG_FILE
    log_good "Installing Kubeflow..."

    curl -LfsS https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/unified-setup/playbooks/sysctl-playbook.yaml | \
    ansible-playbook -i $ANSIBLE_INVENTORY /dev/stdin

    build_kubeflow $TEMP_DIR

    attempts=10
    log "Applying all Kubeflow resources..."
    log "Attempts remaining: $((attempts))"
    while (( attempts > 1 )) && ! "$KUBECTL" apply -f $TEMP_DIR/$KUBEFLOW_MANIFEST; do
        attempts=$((attempts - 1))
        log "Kubeflow installation incomplete."
        log "Attempts remaining: $((attempts))"
        log "Waiting 15 seconds before attempt..."
        sleep 15
    done
    if (( attempts > 1 )) || "$KUBECTL" apply -f $TEMP_DIR/$KUBEFLOW_MANIFEST; then
        log_good "Kubeflow installed."
    else
        log_bad "Error installing Kubeflow."
        false
    fi
fi

if $install_nvidia_gpu_operator; then
    div
    LOG_FILE="$MMAI_SETUP_LOG_DIR/install-nvidia-gpu-operator.log"
    set_log_file $LOG_FILE
    log_good "Installing NVIDIA GPU Operator..."
    "$HELM" repo add nvidia https://helm.ngc.nvidia.com/nvidia
    "$HELM" repo update

    NVIDIA_GPU_OPERATOR_VALUES="$TEMP_DIR/gpu-operator-values.yaml"
    curl -LfsSo $NVIDIA_GPU_OPERATOR_VALUES https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/unified-setup/values/gpu-operator-values.yaml
    if "$HELM" install --wait --create-namespace -n gpu-operator nvidia-gpu-operator nvidia/gpu-operator --version $NVIDIA_GPU_OPERATOR_VERSION \
        -f $NVIDIA_GPU_OPERATOR_VALUES \
        --debug
    then
        log_good "NVIDIA GPU Operator installed."
    else
        log_bad "Error installing NVIDIA GPU Operator."
        NVIDIA_GPU_OPERATOR_LOG_DIR="$MMAI_SETUP_LOG_DIR/nvidia-gpu-operator"
        mkdir $NVIDIA_GPU_OPERATOR_LOG_DIR

        NVIDIA_GPU_OPERATOR_MANIFEST="$NVIDIA_GPU_OPERATOR_LOG_DIR/manifest.yaml"
        helm_manifest -n gpu-operator nvidia-gpu-operator nvidia/gpu-operator --version $NVIDIA_GPU_OPERATOR_VERSION \
            -f $NVIDIA_GPU_OPERATOR_VALUES \
            --include-crds \
            --debug \
            > $NVIDIA_GPU_OPERATOR_MANIFEST

        get_describe_manifest_resources $NVIDIA_GPU_OPERATOR_MANIFEST $NVIDIA_GPU_OPERATOR_LOG_DIR
        false
    fi
fi

if $install_mmcai_cluster; then
    div
    LOG_FILE="$MMAI_SETUP_LOG_DIR/install-mmcai-cluster.log"
    set_log_file $LOG_FILE
    log_good "Installing MMC.AI Cluster..."

    curl -LfsS https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/unified-setup/playbooks/mysql-setup-playbook.yaml | \
    ansible-playbook -i $ANSIBLE_INVENTORY /dev/stdin

    # Create namespaces
    "$KUBECTL" get namespace $RELEASE_NAMESPACE &>/dev/null || "$KUBECTL" create namespace $RELEASE_NAMESPACE
    "$KUBECTL" get namespace $MMCLOUD_OPERATOR_NAMESPACE &>/dev/null || "$KUBECTL" create namespace $MMCLOUD_OPERATOR_NAMESPACE
    "$KUBECTL" get namespace $PROMETHEUS_NAMESPACE &>/dev/null || "$KUBECTL" create namespace $PROMETHEUS_NAMESPACE

    # Create MySQL secret
    if $create_mysql_secret; then
        "$KUBECTL" delete secret -n $RELEASE_NAMESPACE mmai-mysql-secret --ignore-not-found

        # While we only need mysql-root-password, all of these keys are necessary for the secret according to the mysql Helm chart documentation
        "$KUBECTL" create secret generic -n $RELEASE_NAMESPACE mmai-mysql-secret \
            --from-literal=mysql-root-password=$MYSQL_ROOT_PASSWORD \
            --from-literal=mysql-password=$MYSQL_ROOT_PASSWORD \
            --from-literal=mysql-replication-password=$MYSQL_ROOT_PASSWORD
    fi

    if "$HELM" install -n $RELEASE_NAMESPACE mmcai-cluster oci://ghcr.io/memverge/charts/mmcai-cluster --version $MMAI_CLUSTER_VERSION \
        --set billing.database.nodeHostname=$MYSQL_NODE_HOSTNAME \
        --debug
    then
        log_good "MMC.AI Cluster installed."
    else
        log_bad "Error installing MMC.AI Cluster."
        MMAI_CLUSTER_LOG_DIR="$MMAI_SETUP_LOG_DIR/mmcai-cluster"
        mkdir $MMAI_CLUSTER_LOG_DIR

        MMAI_CLUSTER_MANIFEST="$MMAI_CLUSTER_LOG_DIR/manifest.yaml"
        helm_manifest -n $RELEASE_NAMESPACE mmcai-cluster oci://ghcr.io/memverge/charts/mmcai-cluster --version $MMAI_CLUSTER_VERSION \
            --set billing.database.nodeHostname=$MYSQL_NODE_HOSTNAME \
            --include-crds \
            --debug \
            > $MMAI_CLUSTER_MANIFEST

        get_describe_manifest_resources $MMAI_CLUSTER_MANIFEST $MMAI_CLUSTER_LOG_DIR
        false
    fi
fi

if $install_mmcai_manager; then
    div
    LOG_FILE="$MMAI_SETUP_LOG_DIR/install-mmcai-manager.log"
    set_log_file $LOG_FILE
    log_good "Installing MMC.AI Manager..."
    if "$HELM" install -n $RELEASE_NAMESPACE mmcai-manager oci://ghcr.io/memverge/charts/mmcai-manager --version $MMAI_MANAGER_VERSION --debug; then
        log_good "MMC.AI Manager installed."
    else
        log_bad "Error installing MMC.AI Manager."
        MMAI_MANAGER_LOG_DIR="$MMAI_SETUP_LOG_DIR/mmcai-manager"
        mkdir $MMAI_MANAGER_LOG_DIR

        MMAI_MANAGER_MANIFEST="$MMAI_MANAGER_LOG_DIR/manifest.yaml"
        helm_manifest -n $RELEASE_NAMESPACE mmcai-manager oci://ghcr.io/memverge/charts/mmcai-manager --version $MMAI_MANAGER_VERSION \
            --include-crds \
            --debug \
            > $MMAI_MANAGER_MANIFEST

        get_describe_manifest_resources $MMAI_MANAGER_MANIFEST $MMAI_MANAGER_LOG_DIR
        false
    fi
fi

div
log_good "Done!"
