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
        log_bad "Helm login was unsuccessful. Please provide an ${SECRET_YAML} that allows helm login."
        div
        log "Report:"
        cat ${SECRET_YAML}
        div
        exit 1
    fi
}

if [[ -f "mmcai-ghcr-secret-internal.yaml" ]]; then
    kubectl apply -f mmcai-ghcr-secret-internal.yaml
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
helm install --debug -n $NAMESPACE mmcai-cluster oci://ghcr.io/memverge/charts/internal/mmcai-cluster --devel \
    --set billing.database.nodeHostname=$mysql_node_hostname

## install mmc.ai management
helm install --debug -n $NAMESPACE mmcai-manager oci://ghcr.io/memverge/charts/internal/mmcai-manager --devel
