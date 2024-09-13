#!/bin/bash

source logging.sh

NAMESPACE="mmcai-system"
SECRET_YAML="mmcai-ghcr-secret.yaml"
SECRET_INTERNAL_YAML="mmcai-ghcr-secret-internal.yaml"

install_internal=false
install_repository="oci://ghcr.io/memverge/charts"

MMCAI_GHCR_SECRET=""

## helper functions for jq install and cleanup

function cleanup() {
    sudo rm -rf /usr/local/bin/jq
    trap - EXIT
    exit
}

trap cleanup EXIT

function install_jq() {
    wget -O jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64
    chmod +x jq
    sudo cp jq /usr/local/bin/
}


function usage () {
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
            MMCAI_GHCR_SECRET="$OPTARG"
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


function autofind_secret() {
    # First check for mmcai-ghcr-secret-internal.yaml.
    # If that is present, pull it; if not, check without -internal.
    if [ -f ${SECRET_INTERNAL_YAML} ]; then
        MMCAI_GHCR_SECRET=$(pwd)/${SECRET_INTERNAL_YAML}
    elif [ -f ${SECRET_YAML} ]; then
        MMCAI_GHCR_SECRET=$(pwd)/${SECRET_YAML}
    else
        # No local secret and no OPTARG; exit
        if [ -z "$MMCAI_GHCR_SECRET" ]; then
            log_bad "Please provide a path to ${SECRET_YAML}."
            usage
            exit 1
        fi
    fi

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
}


function setup_mysql_directories() {
    log_good "Please provide information for billing database:"
    read -p "MySQL database node hostname: " mysql_node_hostname
    read -sp "MySQL root password: " mysql_root_password
    echo ""

    log_good "Creating directories for billing database:"
    div 

    wget -O mysql-pre-setup.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/mysql-pre-setup.sh
    chmod +x mysql-pre-setup.sh
    ./mysql-pre-setup.sh
}


### Until setup_mmcai_secret, these are helper functions for
### interfacing with helm and pulling credentials from a dockerconfigjson

# Log into helm using the credentials from the image pull secret.
function helm_login() {
    install_jq

    # Extract creds
    secret_json=$(
        kubectl get secret memverge-dockerconfig -n mmcai-system --output="jsonpath={.data.\.dockerconfigjson}" |
        base64 --decode
    )
    secret_user=$(echo ${secret_json} | jq -r '.auths."ghcr.io/memverge".username')
    secret_token=$(echo ${secret_json} | jq -r '.auths."ghcr.io/memverge".password')

    # Attempt login
    if echo $secret_token | helm registry login ghcr.io/memverge -u $secret_user --password-stdin; then
        log_good "Helm login was successful."
    else
        log_bad "Helm login was unsuccessful. Please provide an ${SECRET_YAML} that allows helm login."
        log "Report:"
        cat ${SECRET_YAML}
        exit 1
    fi
}

function helm_poke() {
    attempts=1
    limit=5

    log "Will attempt to pull $1 $attempt times..."
    until helm pull --devel $1 2>&1 > /dev/null; do
        log "Attempt $attempts failed."
    
        attempts=$((attempts + 1))
        if [ $attempts -gt $limit ]; then
            return 1
        fi
    
        sleep 1
    done

    log "Attempt $attempts succeeded."
    return 0
}

function helm_install() {
    # Pull the charts via helm poke, then deploy via helm install.

    if ! helm_poke ${install_repository}/mmcai-cluster; then
        log_bad "Could not pull mmcai-cluster! Try this script again, and if the issue persists, contact support@memverge.com."
        exit 1
    fi

    if ! helm_poke ${install_repository}/mmcai-manager; then
        log_bad "Could not pull mmcai-manager! Try this script again, and if the issue persists, contact support@memverge.com."
        rm -rf mmcai-cluster*.tgz
        exit 1
    fi

    mmcai_cluster_tgz=$(ls mmcai-cluster*.tgz | head -n 1)
    mmcai_manager_tgz=$(ls mmcai-manager*.tgz | head -n 1)

    helm install $install_flags -n $NAMESPACE mmcai-cluster $mmcai_cluster_tgz \
        --set billing.database.nodeHostname=$mysql_node_hostname

    helm install $install_flags -n $NAMESPACE mmcai-manager $mmcai_manager_tgz

    rm -rf $mmcai_cluster_tgz $mmcai_manager_tgz
}

function determine_install_type() {
    # mmcai-ghcr-secret may allow user to pull internal charts.
    # If so, ask user if they want to pull internal or external.
    if helm_poke oci://ghcr.io/memverge/charts/internal/mmcai-manager; then
        rm mmcai-manager*
        log_good "Your ${SECRET_YAML} allows you to pull internal images."
        log_good "Would you like to install internal builds on your cluster? [Y/n]:"
        
        read -p "" install_internal
        case $install_internal in
            [Nn]* ) install_internal=false;;
            * ) install_internal=true;;
        esac
    elif helm_poke oci://ghcr.io/memverge/charts/mmcai-manager; then
        rm mmcai-manager*
        log_good "Your ${SECRET_YAML} allows you to pull customer images."
    else
        log_bad "Your ${SECRET_YAML} does not allow you to pull images. Please contact MemVerge customer support."
        exit 1
    fi

    install_flags="--debug"

    if $install_internal; then
        install_repository="oci://ghcr.io/memverge/charts/internal"
        install_flags="--debug --devel"
    fi

    log "Based on ${SECRET_YAML} credentials, will install from $install_repository."
}

function setup_mmcai_secret() {
    log_good "Creating namespaces, and applying image pull secrets if present..."

    if [[ -f "${MMCAI_GHCR_SECRET}" ]]; then
        kubectl apply -f ${MMCAI_GHCR_SECRET}
        helm_login
        determine_install_type
        kubectl create namespace monitoring
    else
        kubectl create ns $NAMESPACE
        kubectl create ns mmcloud-operator-system
        kubectl create namespace monitoring
    fi
}


function setup_mysql_secret() {
    log_good "Creating mysql secret..."

    kubectl -n $NAMESPACE get secret mmai-mysql-secret &>/dev/null || \
    # While we only need mysql-root-password, all of these keys are
    # necessary for the secret according to the mysql Helm chart documentation
    kubectl -n $NAMESPACE create secret generic mmai-mysql-secret \
        --from-literal=mysql-root-password=$mysql_root_password   \
        --from-literal=mysql-password=$mysql_root_password        \
        --from-literal=mysql-replication-password=$mysql_root_password
}


function do_install() {
    log_good "Installing charts..."

    helm_install
}


div

log "Welcome to MMC.AI setup!"

div

get_opts ${@}

div

autofind_secret

div

setup_mysql_directories

div

setup_mmcai_secret

div

setup_mysql_secret

div

do_install