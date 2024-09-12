#!/bin/bash

source logging.sh

## welcome message

div
log "Welcome to MMC.AI setup!"
div

NAMESPACE="mmcai-system"
SECRET_YAML="mmcai-ghcr-secret.yaml"
SECRET_INTERNAL_YAML="mmcai-ghcr-secret-internal.yaml"

function usage () {
    div
    echo "$0 [-f yaml]: MMC.AI setup wizard."
    echo "-f: takes a path to ${SECRET_YAML}."
    echo "    By default, the script checks if ${SECRET_YAML} exists in the current directory."
    echo "    If not, then this argument must be provided."
    div
}

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

# First check for mmcai-ghcr-secret-internal.yaml.
# If that is present, pull it; if not, check without -internal.
if [ -f ${SECRET_INTERNAL_YAML} ]; then
    MMCAI_GHCR_SECRET=$(pwd)/${SECRET_INTERNAL_YAML}
elif [ -f ${SECRET_YAML} ]; then
    MMCAI_GHCR_SECRET=$(pwd)/${SECRET_YAML}
else
    # No local secret and no OPTARG; exit
    if [ -z "$MMCAI_GHCR_SECRET" ]; then
        div
        log_bad "Please provide a path to ${SECRET_YAML}."
        usage
        exit 1
    fi
fi

div
log_good "Found image pull secret ${MMCAI_GHCR_SECRET}."
log_good "Do you want to use these credentials to set up MMC.AI? [Y/n]"
read -p "" $continue
case $continue in
    Nn)
        log_good "Exiting setup..."
        sleep 1
        exit 0
        ;;
    *)
        log_good "Continuing setup with credentials in ${MMCAI_GHCR_SECRET}..."
        ;;
esac

div
log_good "Please provide information for billing database:"
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
    if helm registry login ghcr.io/memverge -u $secret_user -p $secret_token; then
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

function determine_install_type() {
    # mmcai-ghcr-secret may allow user to pull internal charts.
    # If so, ask user if they want to pull internal or external.
    helm pull oci://ghcr.io/memverge/charts/internal/mmcai-cluster --devel
    if ls mmcai-cluster* > /dev/null 2>&1; then
        rm mmcai-cluster*

        div
        log_good "Your ${SECRET_YAML} allows you to pull internal images."
        log_good "Would you like to install internal builds on your cluster? [Y/n]:"
        
        read -p "" install_internal
        case $install_internal in
            [Nn]* ) install_internal=false;;
            * ) install_internal=true;;
        esac
    fi

    if $install_internal; then
        install_repository="oci://ghcr.io/memverge/charts/internal"
    fi

    div
    log "Based on ${SECRET_YAML} credentials, will install from $install_repository."
}

if [[ -f "${MMCAI_GHCR_SECRET}" ]]; then
    kubectl apply -f ${MMCAI_GHCR_SECRET}
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

## install latest mmc.ai system
helm install --debug -n $NAMESPACE mmcai-cluster ${install_repository}/mmcai-cluster \
    --set billing.database.nodeHostname=$mysql_node_hostname

## install latest mmc.ai management
helm install --debug -n $NAMESPACE mmcai-manager ${install_repository}/mmcai-manager
