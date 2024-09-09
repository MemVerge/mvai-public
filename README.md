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
git clone https://github.com/NVIDIA/deepops.git
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
  In order to have the Kubernetes node names match with the names of the servers in the cluster, it is best to let `<host-N-name>` be the domain name of the remote host. You can determine a host's domain by running the `hostname` command (without the optional `-f` flag, which prints the fully qualified domain name) on each machine.
- **`[kube-master]`**
  The `<host-name>` of the node in the cluster where Kubernetes' control plane will run. This is most likely the provisioning machine.
- **`[etcd]`**
  Holds the node, or nodes, that will host Kubernetes' `etcd` key-value store. This is also, most likely, the provisioning machine.
- **`[kube-node]`**
  Should contain the cluster's "worker nodes" -- that is, nodes that do not appear in `[kube-master]`, but are expected to run workloads.

## Installing Kubernetes

Once Ansible configuration is complete, copy these commands into your terminal to install Kubernetes:
```bash
wget -O logging.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/logging.sh
wget -O deepops-setup.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/deepops-setup.sh
chmod +x deepops-setup.sh
./deepops-setup.sh
```

## Installing Kubeflow

Download and run `kubeflow-setup.sh` on a node with kubectl and kustomize:
```bash
wget -O logging.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/logging.sh
wget -O git-clone.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/git-clone.sh
wget -O kubeflow-setup.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/kubeflow-setup.sh
chmod +x kubeflow-setup.sh
./kubeflow-setup.sh
```

The following command prints the port for the Kubeflow Central Dashboard:
```bash
echo $(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
```

Using this port, the URL `http://<node-ip>:<port>` will fetch the Kubeflow Central Dashboard, where `<node-ip>` is the IPv4 address of any node on the cluster.


## Installing NVIDIA GPU Operator

Download and run `nvidia-gpu-operator-setup.sh` on the node used to manage Helm installations:
```bash
wget -O logging.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/logging.sh
wget -O gpu-operator-values.yaml https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/gpu-operator-values.yaml
wget -O nvidia-gpu-operator-setup.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/nvidia-gpu-operator-setup.sh
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

#### (Internal) Helm Login Secrets
In order to download the pre-release packages, MemVerge team members must authenticate with the Github container registry.

First, create a personal access token on this Github page: https://github.com/settings/tokens

Ctrl-f to find `read:packages` and select the checkbox.

Then press "**Generate token**."

Copy the token that is highlighted in green. Save it to your local machine if you do not want to create a new token during reinstallation.

Then run the following command:

``` bash
helm registry login ghcr.io/memverge/charts
# Username: <github-username>
# Password: <personal-access-token>
```

### Image Pull Secrets

Copy the `mmcai-ghcr-secret.yaml` file provided by MemVerge to the node with `kubectl` access (i.e., the "control plane node"). Then, deploy its image pull credentials to the cluster like so:
```bash
kubectl apply -f mmcai-ghcr-secret.yaml
```

### Cluster Components

#### Billing Database
Download and run `mysql-pre-setup.sh` on the control plane node:
```bash
wget -O logging.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/logging.sh
wget -O mysql-pre-setup.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/mysql-pre-setup.sh
chmod +x mysql-pre-setup.sh
./mysql-pre-setup.sh
```

#### MMC.AI Cluster and Management Planes
Download and run `mmcai-setup.sh` on the control plane node:
``` bash
wget -O logging.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/logging.sh
wget -O mmcai-setup.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/mmcai-setup.sh
chmod +x mmcai-setup.sh
./mmcai-setup.sh
# Answer prompts as needed.
```

Once deployed, the MMC.AI dashboard should be accessible at `http://<control-plane-ip>:32323`.

# MMC.AI Reset Guide

If the MMC.AI installation is in a bad state, you can perform a full reinstall with the following script. The `ghcr` secret file from above must be provided to the script via the `-f` option.

```bash
wget -O logging.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/logging.sh
wget -O mmcai-reset.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/mmcai-teardown.sh
chmod +x mmcai-teardown.sh
./mmcai-reset.sh -f mmcai-ghcr-secret.yaml
```

# MMC.AI Teardown Guide

Download and run the interactive `mmcai-teardown.sh` script on the control plane node.

Some teardown operations are dangerous and may cause data loss or other installations in the cluster to malfunction, if they rely on the same resources.
If you have nothing else installed in the cluster and want to remove everything, answer 'y' to each prompt.

You will have a chance to confirm your changes after making your selections:
```bash
wget -O logging.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/logging.sh
wget -O mmcai-teardown.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/mmcai-teardown.sh
chmod +x mmcai-teardown.sh
./mmcai-teardown.sh
```
