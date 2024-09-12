#!/bin/bash

source logging.sh

function usage () {
    div
    log "Welcome to the MMC.AI reset wizard."
    log "The purpose of this script is to reinstall the MMC.AI stack if it enters a bad state."
    div
    log "Usage: $0 -f /path/to/mmcai-ghcr-secret.yaml"
}

usage

NAMESPACE="mmcai-system"

confirm_selection=false
confirm_mysql_database=false

while getopts "f:" opt; do
  case $opt in
    f)
        MMCAI_GHCR_SECRET="$OPTARG"
        ;;
    \?)
        div
        log_bad "Invalid option: -$OPTARG" >&2
        usage
        exit 1
        ;;
    :)
        div
        log_bad "Option -$OPTARG requires an argument." >&2
        usage
        exit 1
        ;;
  esac
done

if [ -z "$MMCAI_GHCR_SECRET" ]; then
    log_bad "Please provide a path to mmcai-ghcr-secret.yaml."
    usage
    exit 1
fi

div
read -p "Are you sure you want to reset all MMC.AI components? This will delete your current configurations. [Y/n]:" confirm_selection
case $confirm_selection in
    [Yy]* ) confirm_selection=true;;
    * ) confirm_selection=false;;
esac

if ! $confirm_selection; then
    div
    log "Exiting..."
    exit 1
fi

# Uninstall helm charts
function uninstall_mmai_charts () {
    helm uninstall mmcai-cluster -n $NAMESPACE --timeout 1m0s --ignore-not-found
    if [ $? -ne 0 ]; then
        div
        log_bad "MMC.AI cluster helm chart uninstallation failed."
    fi

    helm uninstall mmcai-manager -n $NAMESPACE --timeout 1m0s --ignore-not-found
    if [ $? -ne 0 ]; then
        div
        log_bad "MMC.AI manager helm chart uninstallation failed."
    fi
}

function uninstall_mmai_ns () {
    # Then, remove namespaces
    div
    log "Removing MMC.AI namespaces..."
    kubectl delete ns $NAMESPACE mmcloud-operator-system --ignore-not-found
}

function uninstall_mmai_departments() {
    # Remove department CRDs
    div
    log "Removing MMC.AI departments..."
    kubectl delete crd departments.mmc.ai --ignore-not-found
}

function uninstall_dependency_charts () {
    # Remove the gpu-operator.
    # Uninstalling the helm chart may fail -- just keep chugging
    div
    log "Removing NVIDIA GPU Operator..."
    kubectl delete crd nvidiadrivers.nvidia.com --ignore-not-found
    kubectl delete crd clusterpolicies.nvidia.com --ignore-not-found
    helm uninstall -n gpu-operator nvidia-gpu-operator --ignore-not-found
    kubectl delete namespace gpu-operator --ignore-not-found
    # NFD
    kubectl delete crd nodefeatures.nfd.k8s-sigs.io --ignore-not-found
    kubectl delete crd nodefeaturerules.nfd.k8s-sigs.io --ignore-not-found
}

function uninstall_dependency_ns () {
    # Remove the gpu-operator and monitoring namespaces
    div
    log "Removing dependency namespaces..."
    kubectl delete ns monitoring gpu-operator
}

function uninstall_mysql () {
    div
    log_good "Removing billing database..."
    wget -O mysql-teardown.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/mysql-teardown.sh
    chmod +x mysql-teardown.sh
    ./mysql-teardown.sh
    rm mysql-teardown.sh
}

function reinstall_mmai_secret() {
    div
    log "Applying $MMCAI_GHCR_SECRET..."
    kubectl apply -f $MMCAI_GHCR_SECRET
    # MMCAI_GHCR_SECRET should have created the mmcai-system and mmcloud-operator-system namespaces
    # Therefore create monitoring by hand.
    kubectl create namespace monitoring
}

function reinstall_mysql_secret() {
    div
    read -p "MySQL database node hostname: " mysql_node_hostname
    read -sp "MySQL root password: " MYSQL_ROOT_PASSWORD
    echo ""

    kubectl -n $NAMESPACE create secret generic mmai-mysql-secret \
        --from-literal=mysql-root-password=$MYSQL_ROOT_PASSWORD \
        --from-literal=mysql-password=$MYSQL_ROOT_PASSWORD \
        --from-literal=mysql-replication-password=$MYSQL_ROOT_PASSWORD
}


function reinstall_nvidia_operator () {
    ## Reinstall the GPU operator
    wget -O gpu-operator-values.yaml https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/gpu-operator-values.yaml
    wget -O nvidia-gpu-operator-setup.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/nvidia-gpu-operator-setup.sh
    chmod +x nvidia-gpu-operator-setup.sh
    ./nvidia-gpu-operator-setup.sh
}


function reinstall_mysql () {
    ## Reinstall the mysql directory
    wget -O mysql-pre-setup.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/mysql-pre-setup.sh
    chmod +x mysql-pre-setup.sh
    ./mysql-pre-setup.sh
}


function reinstall_mmai_charts () {
    ## Reinstall the charts
    helm install -n $NAMESPACE mmcai-cluster oci://ghcr.io/memverge/charts/mmcai-cluster \
        --set billing.database.nodeHostname=$mysql_node_hostname \
        --debug 2> mmcai-cluster-debug.log

    helm install -n $NAMESPACE mmcai-manager oci://ghcr.io/memverge/charts/mmcai-manager \
        --debug 2> mmcai-manager-debug.log
}

function mmcai_reset() {
    uninstall_mmai_charts
    uninstall_mmai_ns
    uninstall_mmai_departments
    uninstall_dependency_charts
    uninstall_dependency_ns
    uninstall_mysql

    div
    log_good "Removed all MMC.AI installation components. Reinstalling stack..."

    reinstall_mmai_secret
    reinstall_mysql_secret
    reinstall_nvidia_operator
    reinstall_mysql
    reinstall_mmai_charts
}

function verify_installation () {
    ## Check for our + kueue's CRDs

    CRDS_PATH='
        mmcai-cluster/crds/
        mmcai-cluster/charts/kueue/templates/crd/
        '
    CRDS=$(kubectl get crds | tail -n +2 | awk '{print $1}')
    CRDS_MISSING=false

    helm pull oci://ghcr.io/memverge/charts/mmcai-cluster --version 0.1.0 --untar

    div
    log "Checking if CRDs have been installed..."

    ## Get the CRDs from those directories -> check if they appear in the CRD list.

    for path in $CRDS_PATH; do
        crd_regex='name: \([a-z]\|-\|[0-9]\)\+\.\(\([a-z]\|-\|[0-9]\)\+\.\?\)\+'
                # "name:" denotes the start of CRD name
                # ignore the \, they're escape characters.
                # this boils down to:
                #    ([a-z] | - | [0-9])+ . ([a-z] | - | [0-9])+ .?
                #    alphanum or dash, followed by period, followed by alphanum, last period optional
        crd_list=$(grep "$crd_regex" "$path" | awk '{print $3}')
        for crd in $crd_list; do
            div
            log "Check CRD $crd:"

            kubectl get crd $crd
            if [ $? -ne 0 ]; then
                log_bad "Error: CRD $crd is missing"
                CRDS_MISSING=true
            else
                log_good "OK: CRD $crd is present"
            fi

            if [ "$CRDS_MISSING" == "true" ]; then
                log_bad "At least one CRD was missing. Consider re-running this script."
                exit 1
            fi
        done
    done

    log_good "All CRDs have installed."
}

mmcai_reset
verify_installation