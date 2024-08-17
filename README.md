# MMC.AI Setup Guide

## Installation prerequisites

NVIDIA’s DeepOps project uses Ansible to deploy Kubernetes onto host machines. Ansible is an automation tool that allows system administrators to run commands on multiple machines, while interacting with only one host, called the “provisioning machine.”

#### Setting up user accounts

A user with `sudo` permissions is needed on each host where Kubernetes will be installed.

Log into each target host as `root`. Then, execute the following commands:

```bash
# 'mmai-admin' can be any username.
# Fill out name and password prompts as needed.
sudo adduser mmai-admin

# Adds the new user to the sudoers group.
sudo usermod -aG sudo mmai-admin

# Allows the new user to execute 'sudo <cmd>' without prompting for a password.
echo "mmai-admin ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/mmai-admin
```

#### Enabling private-key SSH

To allow Ansible to connect to remote hosts without querying for a password, private-key SSH connections must be enabled. From the provisioning machine, follow these steps:
```bash
# Generate a public/private keypair for the current user;
# Can leave all fields empty.
ssh-keygen

# Substitute <username> with the name of a user account on server <host>;
# provide the requisite password. If the steps above were followed, then
# <username> will be 'mmai-admin'.
ssh-copy-id <username>@<host>
```

These instructions come from [NVIDIA’s guide on Ansible](https://github.com/NVIDIA/deepops/blob/master/docs/deepops/ansible.md#passwordless-configuration-using-ssh-keys), which contains more information.

## Ansible Installation with DeepOps

The following set of commands will install Ansible on the provisioning machine. They must be run as a regular user.
```bash
git clone git@github.com:NVIDIA/deepops.git
cd ./deepops
git checkout 23.08
./scripts/setup.sh
```

## Editing Ansible Configurations

Once Ansible installation is complete, `deepops/config/inventory` must be configured by the system admin.

#### `deepops/config/inventory`

This file defines which hosts will be used for Kubernetes installation.

Within there are four relevant headers:

- **`[all]`**
  A list of the hosts that will participate in the Kubernetes cluster.
  For example:
  ```
    [all]
    <host-1-name>   ansible_host=<host-1-ip-address>
    <host-2-name>   ansible_host=<host-2-ip-address>
    # The following will configure the local machine as a target:
    # host-1        ansible_host=localhost
  ```
  In order to have the Kubernetes node names match with the names of the servers in the cluster, it is best to let `<host-N-name>` be the domain name of the remote host. You can determine a host's domain by running the `hostname` command on each machine.
- **`[kube-master]`**
  The `<host-name>` of the node in the cluster where Kubernetes' control plane will run. This is most likely the provisioning machine.
- **`[etcd]`**
  Holds the node, or nodes, that will host Kubernetes' `etcd` key-value store. This is also, most likely, the provisioning machine.
- **`[kube-node]`**
  Should contain the cluster's "worker nodes" -- that is, nodes that do not appear in `[kube-master]`, but are expected to run workloads. 

## Installing Kubernetes

Once Ansible configuration is complete, copy these commands into your terminal to install Kubernetes and NVIDIA's NFS client provisioner:
```bash
wget -O logging.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/setup/logging.sh
wget -O deepops-setup.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/setup/deepops-setup.sh
chmod +x deepops-setup.sh
./deepops-setup.sh
```

## Installing Kubeflow

Download and run `kubeflow-setup.sh` on a node with kubectl and kustomize:
```bash
wget -O logging.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/setup/logging.sh
wget -O git-clone.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/setup/git-clone.sh
wget -O kubeflow-setup.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/setup/kubeflow-setup.sh
chmod +x kubeflow-setup.sh
./kubeflow-setup.sh
```
## Installing NVIDIA GPU Operator

Download and run `nvidia-gpu-operator-setup.sh` on the node used to manage Helm installations:
```bash
wget -O logging.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/setup/logging.sh
wget -O gpu-operator-values.yaml https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/setup/gpu-operator-values.yaml
wget -O nvidia-gpu-operator-setup.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/setup/nvidia-gpu-operator-setup.sh
chmod +x nvidia-gpu-operator-setup.sh
./nvidia-gpu-operator-setup.sh
```

## Installing MMC.AI

> **Important:**
> The following prerequisites are necessary if you did not follow the instructions above:
> 1. Kubernetes set up.
> 2. [Default StorageClass](https://kubernetes.io/docs/concepts/storage/storage-classes/#default-storageclass) set up in cluster.
> 3. [Kubeflow](https://www.kubeflow.org/docs/started/installing-kubeflow/) installed in cluster.
> 4. NVIDIA GPU Operator installed via Helm in cluster with overrides from `gpu-operator-values.yaml`.
> 5. Node(s) in cluster with [Helm](https://helm.sh/docs/intro/quickstart/) installed.

### Image Pull Secrets

Copy the `mmcai-ghcr-secret.yaml` file provided by MemVerge to the node with `kubectl` access (i.e., the "control plane node"). Then, deploy its image pull credentials to the cluster like so:
```bash
kubectl apply -f mmcai-ghcr-secret.yaml
```

### Cluster Components

#### Billing Database
Download and run `mysql-pre-setup.sh` on the node used for the billing database:
> **Tip:**
> `mysql-pre-setup.sh` will manually prompt for the hostname of the current node.

```bash
wget -O logging.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/setup/logging.sh
wget -O mysql-pre-setup.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/setup/mysql-pre-setup.sh
chmod +x mysql-pre-setup.sh
./mysql-pre-setup.sh
```


#### MMC.AI Cluster and Management Planes
Download and run `mmcai-setup.sh` on the control plane node:

``` bash
wget -O logging.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/setup/logging.sh
wget -O mmcai-setup.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/setup/mmcai-setup.sh
chmod +x mmcai-setup.sh
./mmcai-setup.sh
# Answer prompts as needed.
```

Once deployed, the MMC.AI dashboard should be accessible at `http://<control-plane-ip>:32323`.


# MMC.AI Teardown Guide

## Uninstalling MMC.AI

### Management Center

On the control plane node:
```bash
helm uninstall -n mmcai-system mmcai-manager
```

### Cluster

Remove CRDs and CRs:
> **Caution:**
> Removal of CRDs cascades to all associated resources. Skip this step if you wish to keep custom resources.
>
> **Important:**
> Manual intervention may be needed if custom resources associated with CRDs still exist and you have already uninstalled the controllers responsible for their finalizers.

```bash
# MMC.AI
kubectl delete crd departments.mmc.ai
kubectl delete crd engines.mmcloud.io

kubectl delete crd admissionchecks.kueue.x-k8s.io
kubectl delete crd clusterqueues.kueue.x-k8s.io
kubectl delete crd localqueues.kueue.x-k8s.io
kubectl delete crd multikueueclusters.kueue.x-k8s.io
kubectl delete crd multikueueconfigs.kueue.x-k8s.io
kubectl delete crd provisioningrequestconfigs.kueue.x-k8s.io
kubectl delete crd resourceflavors.kueue.x-k8s.io
kubectl delete crd workloadpriorityclasses.kueue.x-k8s.io
kubectl delete crd workloads.kueue.x-k8s.io

# Prometheus
kubectl delete crd alertmanagerconfigs.monitoring.coreos.com
kubectl delete crd alertmanagers.monitoring.coreos.com
kubectl delete crd podmonitors.monitoring.coreos.com
kubectl delete crd probes.monitoring.coreos.com
kubectl delete crd prometheusagents.monitoring.coreos.com
kubectl delete crd prometheuses.monitoring.coreos.com
kubectl delete crd prometheusrules.monitoring.coreos.com
kubectl delete crd scrapeconfigs.monitoring.coreos.com
kubectl delete crd servicemonitors.monitoring.coreos.com
kubectl delete crd thanosrulers.monitoring.coreos.com
```

Remove Helm installation:
```
helm uninstall -n <RELEASE_NAMESPACE> <RELEASE_NAME>
```

Remove secrets:
```
kubectl delete secret -n <RELEASE_NAMESPACE> memverge-dockerconfig
kubectl delete secret -n <MMCLOUD_OPERATOR_NAMESPACE> memverge-dockerconfig
kubectl delete secret -n <RELEASE_NAMESPACE> mysql-secret
```

Remove namespaces:
```
kubectl delete namespace <RELEASE_NAMESPACE> 
kubectl delete namespace <MMCLOUD_OPERATOR_NAMESPACE>
kubectl delete namespace <PROMETHEUS_NAMESPACE>
```

Remove billing database data:
```
rm -rf /mnt/disks/mmai-mysql-billing
```

## Uninstalling NVIDIA GPU Operator

Remove CRDs and CRs:
> **Caution:**
> Removal of CRDs cascades to all associated resources. Skip this step if you wish to keep custom resources.
>
> **Important:**
> Manual intervention may be needed if custom resources associated with CRDs still exist and you have already uninstalled the controllers responsible for their finalizers.

```bash
# NVIDIA
kubectl delete crd clusterpolicies.nvidia.com
kubectl delete crd nvidiadrivers.nvidia.com

# NFD
kubectl delete crd nodefeatures.nfd.k8s-sigs.io
kubectl delete crd nodefeaturerules.nfd.k8s-sigs.io
```

Remove Helm installation:

```bash
helm uninstall -n gpu-operator nvidia-gpu-operator
```

If uninstallation of the Helm chart fails partway, delete the gpu-operator namespace to remove all associate Kubernetes pods and resources:

```
kubectl delete ns gpu-operator
```

## Uninstalling Kubeflow

```bash
wget -O logging.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/setup/logging.sh
wget -O kubeflow-teardown.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/setup/kubeflow-teardown.sh
chmod +x kubeflow-teardown.sh
./kubeflow-teardown.sh
```
