#!/bin/bash

source logging.sh

## welcome message

div
log "Welcome to MMC.AI setup!"
div

NAMESPACE="mmcai-system"

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
log_good "Creating namespaces, and applying image pull secrets if present..."

install_internal=false
install_repository="oci://ghcr.io/memverge/charts"

# Log into helm using the credentials from the image pull secret.
function helm_login() {
    # Extract creds
    secret_json=$(
        kubectl get secret memverge-dockerconfig -n mmcai-system --output="jsonpath={.data.\.dockerconfigjson}" |
        base64 --decode
    )
    secret_user=$(echo ${secret_json} | jq -r '.auths."ghcr.io/memverge".username')
    secret_token=$(echo ${secret_json} | jq -r '.auths."ghcr.io/memverge".password')

    # Attempt login
    if helm login ghcr.io/memverge -u $secret_user -p $secret_token; then
        div
        log_good "Helm login was successful."
    else
        div
        log_bad "Helm login was unsuccessful. Please provide an mmcai-ghcr-secret.yaml that allows helm login."
        div
        log "Report:"
        cat mmcai-ghcr-secret.yaml
        div
        exit 1
    fi
}

function determine_install_type() {
    # mmcai-ghcr-secret may allow user to pull internal charts.
    # If so, ask user if they want to pull internal or external.
    helm pull oci://ghcr.io/memverge/charts/internal/mmcai-cluster --devel
    if ls mmcai-cluster* > /dev/null 2>&1; then
        rm mmcai-cluster*

        div
        log_good "Your mmcai-ghcr-secret.yaml allows you to pull internal images."
        
        read -p "Would you like to install internal builds on your cluster? [Y/n]:" install_internal
        case $install_internal in
            [Nn]* ) install_internal=false;;
            * ) install_internal=true;;
        esac
    fi

    if $install_internal; then
        install_repository="oci://ghcr.io/memverge/charts/internal"
    fi

    div
    log "Based on mmcai-ghcr-secret.yaml credentials, will install from $install_repository"
}

if [[ -f "mmcai-ghcr-secret.yaml" ]]; then
    kubectl apply -f mmcai-ghcr-secret.yaml
    helm_login
    determine_install_type
else
    kubectl create ns $NAMESPACE
    kubectl create ns mmcloud-operator-system
fi

## Create monitoring namespace

kubectl get namespace monitoring &>/dev/null || kubectl create namespace monitoring

div
log_good "Creating mysql secret..."
div

## Create MySQL secret

kubectl -n $NAMESPACE get secret mmai-mysql-secret &>/dev/null || \
# While we only need mysql-root-password, all of these keys are necessary for the secret according to the mysql Helm chart documentation
kubectl -n $NAMESPACE create secret generic mmai-mysql-secret \
    --from-literal=mysql-root-password=$MYSQL_ROOT_PASSWORD \
    --from-literal=mysql-password=$MYSQL_ROOT_PASSWORD \
    --from-literal=mysql-replication-password=$MYSQL_ROOT_PASSWORD

div
log_good "Installing charts..."
div

## install mmc.ai system
helm install --debug -n $NAMESPACE mmcai-cluster ${install_repository}/mmcai-cluster \
    --set billing.database.nodeHostname=$mysql_node_hostname

## install mmc.ai management
helm install --debug -n $NAMESPACE mmcai-manager ${install_repository}/mmcai-manager
