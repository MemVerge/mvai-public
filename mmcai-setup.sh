#!/bin/bash

set -euo pipefail

source common.sh

install_mmcai_manager=false
install_mmcai_cluster=false
install_nvidia_gpu_operator=false
install_kubeflow=false
install_cert_manager=false # Allow instead of kubeflow if not installing mmcai-manager.

confirm_selection=false

# Sanity check.
log "Getting version to check connectivity."
if ! kubectl version; then
    log_bad "Cannot proceed with setup."
    exit 1
else
    log_good "Proceeding with setup."
fi

if kubectl get secret -n $RELEASE_NAMESPACE memverge-dockerconfig; then
    release_namespace_image_pull_secrets_detected=true
else
    release_namespace_image_pull_secrets_detected=false
    log_bad "MemVerge image pull secret in namespace $RELEASE_NAMESPACE not detected."
fi

if kubectl get secret -n $MMCLOUD_OPERATOR_NAMESPACE memverge-dockerconfig; then
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
    kubectl get namespace cert-manager
}
if ! cert_manager_detected; then
    log "cert-manager not detected."
fi

# Determine if Kubeflow is installed.
kubeflow_detected() {
    kubectl get namespace kubeflow
}
if ! kubeflow_detected; then
    log "Kubeflow not detected."
fi

# Determine if nvidia-gpu-operator is installed.
nvidia_gpu_operator_detected() {
    helm list -n gpu-operator -a -q | grep gpu-operator
}
if ! nvidia_gpu_operator_detected; then
    log "NVIDIA GPU Operator not detected."
fi

# Determine if mmcai-cluster is installed.
mmcai_cluster_detected() {
    helm list -n mmcai-system -a -q | grep mmcai-cluster
}
if ! mmcai_cluster_detected; then
    log "MMC.AI Cluster not detected."
fi

# Determine if mmcai-manager is installed.
mmcai_manager_detected() {
    helm list -n mmcai-system -a -q | grep mmcai-manager
}
if ! mmcai_manager_detected; then
    log "MMC.AI Manager not detected."
fi

################################################################################

# Install mmcai-manager?
if ! mmcai_manager_detected; then
    div
    read -p "Install MMC.AI Manager [y/N]:" install_mmcai_manager
    case $install_mmcai_manager in
        [Yy]* ) install_mmcai_manager=true;;
        * ) install_mmcai_manager=false;;
    esac
fi

if $install_mmcai_manager || mmcai_manager_detected; then
    be_mmcai_manager=true
else
    be_mmcai_manager=false
fi

while $be_mmcai_manager && cert_manager_detected && ! kubeflow_detected; do
    # This is true at least as long as we have the hard-coded deepops@example.com.
    echo "MMC.AI Manager requires Kubeflow, which provides cert-manager. Please uninstall existing cert-manager before continuing if you wish to install MMC.AI Manager."
    read -p "Continue setup [Y/n]:" continue_setup
    case $continue_setup in
        [Nn]* ) continue_setup=false;;
        * ) continue_setup=true;;
    esac
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
        read -p "Install MMC.AI Cluster [y/N]:" install_mmcai_cluster
        case $install_mmcai_cluster in
            [Yy]* ) install_mmcai_cluster=true;;
            * ) install_mmcai_cluster=false;;
        esac
    fi
fi

if $install_mmcai_cluster || mmcai_cluster_detected; then
    be_mmcai_cluster=true
else
    be_mmcai_cluster=false
fi

if $install_mmcai_cluster && nvidia_gpu_operator_detected; then
    echo "MMC.AI Cluster requires NVIDIA GPU Operator installed with a specific configuration. If existing NVIDIA GPU Operator was not installed using this script, please uninstall existing NVIDIA GPU Operator before continuing."
    read -p "Continue setup [Y/n]:" continue_setup
    case $continue_setup in
        [Nn]* ) continue_setup=false;;
        * ) continue_setup=true;;
    esac
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
        read -p "Install NVIDIA GPU Operator [y/N]:" install_nvidia_gpu_operator
        case $install_nvidia_gpu_operator in
            [Yy]* ) install_nvidia_gpu_operator=true;;
            * ) install_nvidia_gpu_operator=false;;
        esac
    fi
fi

if $install_mmcai_manager && kubeflow_detected; then
    echo "MMC.AI Manager requires Kubeflow installed with a specific configuration. If existing Kubeflow was not installed using this script, please uninstall existing Kubeflow before continuing."
    read -p "Continue setup [Y/n]:" continue_setup
    case $continue_setup in
        [Nn]* ) continue_setup=false;;
        * ) continue_setup=true;;
    esac
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
        # This is true at least as long as we have the hard-coded deepops@example.com.
        echo "Kubeflow is required by MMC.AI Manager. Kubeflow will be installed."
        install_kubeflow=true
    else
        div
        read -p "Install Kubeflow [y/N]:" install_kubeflow
        case $install_kubeflow in
            [Yy]* ) install_kubeflow=true;;
            * ) install_kubeflow=false;;
        esac
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
        read -p "Install cert-manager (Helm chart) [y/N]:" install_cert_manager
        case $install_cert_manager in
            [Yy]* ) install_cert_manager=true;;
            * ) install_cert_manager=false;;
        esac
    fi
fi

# Get Ansible inventory for components that need it.
if $install_mmcai_cluster || $install_kubeflow; then
    ANSIBLE_INVENTORY=''
    until [ -e $ANSIBLE_INVENTORY ]; do
        read -p "Ansible inventory: " ANSIBLE_INVENTORY
        if ! [ -e $ANSIBLE_INVENTORY ]; then
            log_bad "Path does not exist."
        fi
    done

    if $install_mmcai_cluster; then
        MYSQL_NODE_HOSTNAME=$(ansible-inventory --list -i $ANSIBLE_INVENTORY | jq -r --arg NODE_GROUP "$ANSIBLE_INVENTORY_DATABASE_NODE_GROUP" '.[$NODE_GROUP].hosts[]?')
        while (( $(echo $MYSQL_NODE_HOSTNAME | wc -w) != 1 )); do
            log_bad "Wrong number of $ANSIBLE_INVENTORY_DATABASE_NODE_GROUP nodes in Ansible inventory."
            echo "Number of $ANSIBLE_INVENTORY_DATABASE_NODE_GROUP nodes must be 1. Please fix Ansible inventory before continuing."
            read -p "Continue setup [Y/n]:" continue_setup
            case $continue_setup in
                [Nn]* ) continue_setup=false;;
                * ) continue_setup=true;;
            esac
            if ! $continue_setup; then
                exit 0
            fi
            MYSQL_NODE_HOSTNAME=$(ansible-inventory --list -i $ANSIBLE_INVENTORY | jq -r --arg NODE_GROUP "$ANSIBLE_INVENTORY_DATABASE_NODE_GROUP" '.[$NODE_GROUP].hosts[]?')
        done

        if kubectl get secret -n $RELEASE_NAMESPACE mmai-mysql-secret &>/dev/null; then
            mysql_secret_exists=true
            log "Existing billing database secret found."
        else
            mysql_secret_exists=false
        fi

        if $mysql_secret_exists; then
            echo "Reuse existing billing database secret? If N/n, the existing database secret will be overwritten."
            read -p "Reuse existing secret [Y/n]:" reuse_database_secret
            case $reuse_database_secret in
                [Nn]* ) create_mysql_secret=true;;
                * ) create_mysql_secret=false;;
            esac
        else
            create_mysql_secret=true
        fi

        if $create_mysql_secret; then
            echo "Enter new billing database secret."
            MYSQL_ROOT_PASSWORD=''
            MYSQL_ROOT_PASSWORD_CONFIRMATION='nonempty'
            until [ "$MYSQL_ROOT_PASSWORD" = "$MYSQL_ROOT_PASSWORD_CONFIRMATION" ]; do
                read -sp "Billing database root password:" MYSQL_ROOT_PASSWORD
                read -sp "Confirm database root password:" MYSQL_ROOT_PASSWORD_CONFIRMATION
                if [ "$MYSQL_ROOT_PASSWORD" != "$MYSQL_ROOT_PASSWORD_CONFIRMATION" ]; then
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
read -p "Confirm selection [y/N]:" confirm_selection
case $confirm_selection in
    [Yy]* ) confirm_selection=true;;
    * ) confirm_selection=false;;
esac

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
    log_good "Installing cert-manager..."
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    helm install --wait --create-namespace -n cert-manager cert-manager jetstack/cert-manager --version $CERT_MANAGER_VERSION \
      --set crds.enabled=true
fi

if $install_kubeflow; then
    div
    log_good "Installing Kubeflow..."

    curl https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/playbooks/sysctl-playbook.yaml | \
    ansible-playbook -i $ANSIBLE_INVENTORY /dev/stdin

    log "Cloning Kubeflow manifests..."
    git clone https://github.com/kubeflow/manifests.git $TEMP_DIR/kubeflow --branch $KUBEFLOW_VERSION

    ( # Subshell to change directory.
        cd $TEMP_DIR/kubeflow
        log "Applying all Kubeflow resources..."
        while ! kustomize build example | kubectl apply -f -; do
            log "Kubeflow installation incomplete."
            log "Waiting 15 seconds before attempt..."
            sleep 15
        done
        log "Kubeflow installed."
    )
fi

if $install_nvidia_gpu_operator; then
    div
    log_good "Installing NVIDIA GPU Operator..."
    helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
    helm repo update
    curl https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/gpu-operator-values.yaml | \
    helm install --wait -n gpu-operator nvidia-gpu-operator nvidia/gpu-operator --version $NVIDIA_GPU_OPERATOR_VERSION -f -
fi

if $install_mmcai_cluster; then
    div
    log_good "Installing MMC.AI Cluster..."

    curl https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/playbooks/mysql-setup-playbook.yaml | \
    ansible-playbook -i $ANSIBLE_INVENTORY /dev/stdin

    # Create namespaces
    kubectl get namespace $RELEASE_NAMESPACE &>/dev/null || kubectl create namespace $RELEASE_NAMESPACE
    kubectl get namespace $MMCLOUD_OPERATOR_NAMESPACE &>/dev/null || kubectl create namespace $MMCLOUD_OPERATOR_NAMESPACE
    kubectl get namespace $PROMETHEUS_NAMESPACE &>/dev/null || kubectl create namespace $PROMETHEUS_NAMESPACE

    # Create MySQL secret
    if $create_mysql_secret; then
        kubectl delete secret -n $RELEASE_NAMESPACE mmai-mysql-secret --ignore-not-found

        # While we only need mysql-root-password, all of these keys are necessary for the secret according to the mysql Helm chart documentation
        kubectl create secret generic -n $RELEASE_NAMESPACE mmai-mysql-secret \
            --from-literal=mysql-root-password=$MYSQL_ROOT_PASSWORD \
            --from-literal=mysql-password=$MYSQL_ROOT_PASSWORD \
            --from-literal=mysql-replication-password=$MYSQL_ROOT_PASSWORD
    fi

    helm install -n $RELEASE_NAMESPACE mmcai-cluster oci://ghcr.io/memverge/charts/mmcai-cluster \
        --set billing.database.nodeHostname=$MYSQL_NODE_HOSTNAME
fi

if $install_mmcai_manager; then
    div
    log_good "Installing MMC.AI Manager..."
    helm install -n $RELEASE_NAMESPACE mmcai-manager oci://ghcr.io/memverge/charts/mmcai-manager
fi
