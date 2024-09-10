#!/bin/bash

set -euo pipefail

curl -LfsSo ensure-prerequisites.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/better-logging/util/ensure-prerequisites.sh
curl -LfsSo common.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/better-logging/util/common.sh
curl -LfsSo logging.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/better-logging/util/logging.sh

source ensure-prerequisites.sh
source common.sh
source logging.sh

set_log_directory mmai-teardown-$FILE_TIMESTAMP
set_log_file mmai-teardown.log

remove_mmcai_cluster=false
remove_mmcai_manager=false
remove_cluster_resources=false
remove_billing_database=false
remove_memverge_secrets=false
remove_namespaces=false
remove_prometheus_crds_namespace=false
remove_nvidia_gpu_operator=false
remove_kubeflow=false

force_if_remove_cluster_resources=false

confirm_selection=false

# Sanity check.
log "Getting version to check connectivity."
if ! kubectl version; then
    log_bad "Cannot proceed with teardown."
    exit 1
else
    log_good "Proceeding with teardown."
fi

# Determine if mmcai-cluster and mmcai-manager are installed.
if helm list -n mmcai-system -a -q | grep mmcai-cluster; then
    mmcai_cluster_detected=true
else
    mmcai_cluster_detected=false
    log "MMC.AI Cluster not detected."
fi

if helm list -n mmcai-system -a -q | grep mmcai-manager; then
    mmcai_manager_detected=true
else
    mmcai_manager_detected=false
    log "MMC.AI Manager not detected."
fi

################################################################################

# Remove mmcai-cluster?
if $mmcai_cluster_detected; then
    div
    read -p "Remove MMC.AI Cluster [y/N]:" remove_mmcai_cluster
    case $remove_mmcai_cluster in
        [Yy]* ) remove_mmcai_cluster=true;;
        * ) remove_mmcai_cluster=false;;
    esac
fi

if $remove_mmcai_cluster || ! $mmcai_cluster_detected; then
    no_mmcai_cluster=true
else
    no_mmcai_cluster=false
fi


# Remove mmcai-manager?
if $mmcai_manager_detected; then
    if $no_mmcai_cluster; then
        # mmcai-manager does not work without mmcai-cluster.
        echo "MMC.AI Manager does not work without MMC.AI Cluster. MMC.AI Manager will be removed."
        remove_mmcai_manager=true
    else
        div
        read -p "Remove MMC.AI Manager [y/N]:" remove_mmcai_manager
        case $remove_mmcai_manager in
            [Yy]* ) remove_mmcai_manager=true;;
            * ) remove_mmcai_manager=false;;
        esac
    fi
fi

if $remove_mmcai_manager || ! $mmcai_manager_detected; then
    no_mmcai_manager=true
else
    no_mmcai_manager=false
fi


if $no_mmcai_cluster; then
    # Remove cluster resources?
    div
    if ! $mmcai_cluster_detected; then
        echo_red "MMC.AI Cluster not detected. Removing cluster resources will require force. This may result in an unclean state."
        force_if_remove_cluster_resources=true
    fi

    echo_red "Caution: This will cause data loss!"
    read -p "Remove cluster resources (e.g. node groups, departments, projects, workloads) [y/N]:" remove_cluster_resources
    case $remove_cluster_resources in
        [Yy]* ) remove_cluster_resources=true;;
        * ) remove_cluster_resources=false;;
    esac

    if $remove_cluster_resources && $mmcai_cluster_detected; then
        read -p "Force? This may result in an unclean state [y/N]:" force_if_remove_cluster_resources
        case $force_if_remove_cluster_resources in
            [Yy]* ) force_if_remove_cluster_resources=true;;
            * ) force_if_remove_cluster_resources=false;;
        esac
    fi


    # Remove billing database?
    div
    echo_red "Caution: This will cause data loss!"
    read -p "Remove billing database [y/N]:" remove_billing_database
    case $remove_billing_database in
        [Yy]* ) remove_billing_database=true;;
        * ) remove_billing_database=false;;
    esac
    if $remove_billing_database; then
        echo "Provide an Ansible inventory of nodes (Ansible host group [$ANSIBLE_INVENTORY_DATABASE_NODE_GROUP]) to remove billing databases from."
        ANSIBLE_INVENTORY=''
        until [ -e "$ANSIBLE_INVENTORY" ]; do
            read -p "Ansible inventory: " ANSIBLE_INVENTORY
            if ! [ -e "$ANSIBLE_INVENTORY" ]; then
                log_bad "Path does not exist."
            fi
        done
    fi

    # Remove MemVerge image pull secrets?
    div
    read -p "Remove MemVerge image pull secrets [y/N]:" remove_memverge_secrets
    case $remove_memverge_secrets in
        [Yy]* ) remove_memverge_secrets=true;;
        * ) remove_memverge_secrets=false;;
    esac


    # Remove namespaces?
    if $remove_cluster_resources \
    && $remove_billing_database \
    && $remove_memverge_secrets
    then
        div
        echo_red "Caution: This is dangerous!"
        read -p "Remove MMC.AI namespaces [y/N]:" remove_namespaces
        case $remove_namespaces in
            [Yy]* ) remove_namespaces=true;;
            * ) remove_namespaces=false;;
        esac
    fi


    # Remove Prometheus CRDs and namespace?
    div
    echo_red "Caution: This is dangerous!"
    read -p "Remove Prometheus CRDs and namespace (MMC.AI included dependency) [y/N]:" remove_prometheus_crds_namespace
    case $remove_prometheus_crds_namespace in
        [Yy]* ) remove_prometheus_crds_namespace=true;;
        * ) remove_prometheus_crds_namespace=false;;
    esac


    # Remove NVIDIA GPU Operator?
    div
    echo_red "Caution: This is dangerous!"
    read -p "Remove NVIDIA GPU Operator (MMC.AI standalone dependency) [y/N]:" remove_nvidia_gpu_operator
    case $remove_nvidia_gpu_operator in
        [Yy]* ) remove_nvidia_gpu_operator=true;;
        * ) remove_nvidia_gpu_operator=false;;
    esac


    # Remove Kubeflow?
    div
    echo_red "Caution: This is dangerous!"
    read -p "Remove Kubeflow (MMC.AI standalone dependency) [y/N]:" remove_kubeflow
    case $remove_kubeflow in
        [Yy]* ) remove_kubeflow=true;;
        * ) remove_kubeflow=false;;
    esac
fi

################################################################################

div
echo "COMPONENT: REMOVE"
echo "MMC.AI Manager:" $remove_mmcai_manager
echo "MMC.AI Cluster:" $remove_mmcai_cluster
if $remove_cluster_resources && $force_if_remove_cluster_resources; then
    force_indication='(force)'
else
    force_indication=''
fi
echo "Cluster resources:" $remove_cluster_resources $force_indication
echo "Billing database:" $remove_billing_database
echo "MemVerge image pull secrets:" $remove_memverge_secrets
echo "MMC.AI namespaces:" $remove_namespaces
echo "Prometheus CRDs and namespace:" $remove_prometheus_crds_namespace
echo "NVIDIA GPU Operator:" $remove_nvidia_gpu_operator
echo "Kubeflow:" $remove_kubeflow

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
log_good "Beginning teardown..."

################################################################################

if $remove_mmcai_manager; then
    div
    log_good "Removing MMC.AI Manager..."
    helm uninstall -n $RELEASE_NAMESPACE mmcai-manager --ignore-not-found --debug
fi

if $remove_cluster_resources; then
    div
    log_good "Removing cluster resources..."

    cluster_resource_crds='
        admissionchecks.kueue.x-k8s.io
        clusterqueues.kueue.x-k8s.io
        localqueues.kueue.x-k8s.io
        multikueueclusters.kueue.x-k8s.io
        multikueueconfigs.kueue.x-k8s.io
        provisioningrequestconfigs.kueue.x-k8s.io
        resourceflavors.kueue.x-k8s.io
        workloadpriorityclasses.kueue.x-k8s.io
        workloads.kueue.x-k8s.io
        departments.mmc.ai
    '

    kubectl delete crd $cluster_resource_crds --ignore-not-found &
    cluster_resource_crds_removed=$!

    if $force_if_remove_cluster_resources; then
        for cluster_resource_crd in $cluster_resource_crds; do
            until [ -z "$(kubectl get crd $cluster_resource_crd --ignore-not-found)" ]; do
                namespaces=$(kubectl get namespaces -o custom-columns=:.metadata.name)
                for namespace in $namespaces; do
                    if [ -z "$(kubectl get crd $cluster_resource_crd --ignore-not-found)" ]; then
                        break
                    fi
                    resources=$(kubectl get -n $namespace $cluster_resource_crd -o custom-columns=:.metadata.name)
                    if ! [ -z "$resources" ]; then
                        kubectl patch $cluster_resource_crd -n $namespace $resources --type json --patch='[{ "op": "remove", "path": "/metadata/finalizers" }]'
                    fi
                done
            done
        done
    fi

    wait $cluster_resource_crds_removed

    for cluster_resource_crd in $cluster_resource_crds; do
        if ! [ -z "$(kubectl get crd $cluster_resource_crd --ignore-not-found)" ]; then
            log_bad "CRD $cluster_resource_crd was not removed successfully."
        fi
    done
fi

if $remove_mmcai_cluster; then
    div
    log_good "Removing MMC.AI Cluster..."
    echo "If you selected to remove cluster resources, disregard below messages that resources are kept due to the resource policy:"
    helm uninstall -n $RELEASE_NAMESPACE mmcai-cluster --ignore-not-found --debug
fi

if $remove_billing_database; then
    div
    log_good "Removing billing database..."

    curl -LfsS https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/better-logging/playbooks/mysql-teardown-playbook.yaml | \
    ansible-playbook -i $ANSIBLE_INVENTORY /dev/stdin

    kubectl delete secret -n $RELEASE_NAMESPACE mmai-mysql-secret --ignore-not-found
fi

if $remove_memverge_secrets; then
    div
    log_good "Removing MemVerge image pull secrets..."
    kubectl delete secret -n $RELEASE_NAMESPACE memverge-dockerconfig --ignore-not-found
    kubectl delete secret -n $MMCLOUD_OPERATOR_NAMESPACE memverge-dockerconfig --ignore-not-found
fi

if $remove_namespaces; then
    div
    log_good "Removing MMC.AI namespaces..."
    kubectl delete namespace $RELEASE_NAMESPACE --ignore-not-found
    kubectl delete namespace mmcloud-operator-system --ignore-not-found
fi

if $remove_nvidia_gpu_operator; then
    div
    log_good "Removing NVIDIA GPU Operator..."
    kubectl delete crd nvidiadrivers.nvidia.com --ignore-not-found
    kubectl delete crd clusterpolicies.nvidia.com --ignore-not-found
    helm uninstall -n gpu-operator nvidia-gpu-operator --ignore-not-found --debug
    kubectl delete namespace gpu-operator --ignore-not-found

    # NFD
    kubectl delete crd nodefeatures.nfd.k8s-sigs.io --ignore-not-found
    kubectl delete crd nodefeaturerules.nfd.k8s-sigs.io --ignore-not-found
fi

if $remove_prometheus_crds_namespace; then
    div
    log_good "Removing Prometheus CRDs and namespace..."
    prometheus_crds='
        alertmanagerconfigs.monitoring.coreos.com
        alertmanagers.monitoring.coreos.com
        podmonitors.monitoring.coreos.com
        probes.monitoring.coreos.com
        prometheusagents.monitoring.coreos.com
        prometheuses.monitoring.coreos.com
        prometheusrules.monitoring.coreos.com
        scrapeconfigs.monitoring.coreos.com
        servicemonitors.monitoring.coreos.com
        thanosrulers.monitoring.coreos.com
    '
    for crd in $prometheus_crds; do
        kubectl delete crd $crd --ignore-not-found
    done
    kubectl delete namespace $PROMETHEUS_NAMESPACE --ignore-not-found
fi

if $remove_kubeflow; then
    div
    log_good "Removing Kubeflow..."

    build_kubeflow

    attempts=5
    log "Deleting all Kubeflow resources..."
    log "Attempts remaining: $((attempts))"
    while [ $attempts -gt 0 ] && ! kubectl delete --ignore-not-found -f $TEMP_DIR/$KUBEFLOW_MANIFEST; do
        attempts=$((attempts - 1))
        log "Kubeflow removal incomplete."
        log "Attempts remaining: $((attempts))"
        log "Waiting 15 seconds before attempt..."
        sleep 15
    done
    log "Kubeflow removed."
fi

div
log_good "Done!"
