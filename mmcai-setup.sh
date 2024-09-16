#!/bin/bash

source logging.sh

## welcome message

div
log_good "Welcome to MMC.AI setup!"
div

NAMESPACE="mmcai-system"
MMCAI_GHCR_PATH="./mmcai-ghcr-secret.yaml"

function usage() {
    div
    echo "$0 [-f yaml]: MMC.AI setup wizard."
    echo "    -f: takes a path to ${SECRET_YAML}."
    echo "        By default, the script checks if ${SECRET_YAML} exists in the current directory."
    echo "        If not, then this argument must be provided."
    div
}

function get_opts() {
    while getopts "f:" opt; do
    case $opt in
        f)
            MMCAI_GHCR_PATH="$OPTARG"
            ;;
        \?)
            log_bad "Invalid option: -$OPTARG" >&2
            usage
            exit 1
            ;;
        :)
            log_bad "Option -$OPTARG requires an argument." >&2
            usage
            exit 1
            ;;
    esac
    done
}

function find_secret() {
    if [ -f "$MMCAI_GHCR_PATH" ]; then
        log "Found mmcai-ghcr-secret.yaml in $MMCAI_GHCR_PATH. Continuing..."
        return
    fi

    log_bad "Could not find mmcai-ghcr-secret.yaml. Exiting..."
    
    sleep 1
    
    usage

    exit 1
}

get_opts

find_secret

div
log_good "Please provide information for billing database:"
div

read -p "MySQL database node hostname: " mysql_node_hostname
read -sp "MySQL root password: " MYSQL_ROOT_PASSWORD
echo ""

div
log_good "Creating directories for billing database:"
div

wget -O mysql-pre-setup.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/mysql-pre-setup.sh
chmod +x mysql-pre-setup.sh
./mysql-pre-setup.sh

div
log_good "Creating namespaces if needed..."
div

function helm_login() {
    # Extract creds
    secret_json=$(
        kubectl get secret memverge-dockerconfig -n mmcai-system --output="jsonpath={.data.\.dockerconfigjson}" |
        base64 --decode
    )
    secret_user=$(echo ${secret_json} | jq -r '.auths."ghcr.io/memverge".username')
    secret_token=$(echo ${secret_json} | jq -r '.auths."ghcr.io/memverge".password')

    # Attempt login
    if echo $secret_token | helm registry login ghcr.io/memverge -u $secret_user --password-stdin; then
        div
        log_good "Helm login was successful."
    else
        div
        log_bad "Helm login was unsuccessful."
        log_bad "Please provide an mmcai-ghcr-secret.yaml that allows helm login."
        div
        log "Report:"
        cat mmcai-ghcr-secret.yaml
        div
        exit 1
    fi
}

if [[ -f "mmcai-ghcr-secret.yaml" ]]; then
    kubectl apply -f mmcai-ghcr-secret.yaml
    helm registry logout ghcr.io/memverge
    helm_login
else
    kubectl create ns $NAMESPACE
    kubectl create ns mmcloud-operator-system
fi

## Create monitoring namespace

kubectl get namespace monitoring &>/dev/null || kubectl create namespace monitoring

div
log_good "Creating secrets if needed..."
div

## Create MySQL secret

kubectl -n $NAMESPACE get secret mmai-mysql-secret &>/dev/null || \
# While we only need mysql-root-password, all of these keys are necessary for the secret according to the mysql Helm chart documentation
kubectl -n $NAMESPACE create secret generic mmai-mysql-secret \
    --from-literal=mysql-root-password=$MYSQL_ROOT_PASSWORD \
    --from-literal=mysql-password=$MYSQL_ROOT_PASSWORD \
    --from-literal=mysql-replication-password=$MYSQL_ROOT_PASSWORD

div
log_good "Beginning installation..."
div

## install mmc.ai system
helm install --debug -n $NAMESPACE mmcai-cluster oci://ghcr.io/memverge/charts/mmcai-cluster \
    --version 0.2.0-rc2 \
    --set billing.database.nodeHostname=$mysql_node_hostname

## install mmc.ai management
helm install --debug -n $NAMESPACE mmcai-manager oci://ghcr.io/memverge/charts/mmcai-manager \
    --version 0.2.0-rc2
