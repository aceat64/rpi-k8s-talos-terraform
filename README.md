# Kubernetes on RPI with Talos and Terraform

This repo is a fully working example of deploying a Kubernetes cluster to a handful of Raspberry Pi 4s. We use [Talos](https://talos.dev)
for the OS and building the Kubernetes cluster. After the cluster is bootstraped, we use Terraform deploy various useful services onto the cluster.

## Features

At the end of this tutorial you'll have a fully working Kubernetes cluster with the following services configured and ready to use:
* [Talos](https://talos.dev) - Minimal and hardened operating system and tools that deploy and manage kubernetes nodes/clusters.
  * Virtual (shared) IP address for the talos and Kubernetes endpoints
* [MetalLB](https://metallb.universe.tf) - Load balancers using virtual/shared IPs 
* [metrics-server](https://github.com/kubernetes-sigs/metrics-server) - Provide metrics for Kubernetes autoscaling (e.g. horizontal pod autoscaler)
* [cert-manager](https://cert-manager.io/) - Automated TLS certificate management
* [Rook-Ceph](https://rook.io/) - Distributed block, object and file storage
* [Prometheus](https://prometheus.io/) - Monitoring and alerting
  * Full monitoring of your cluster! We gather metrics from just about every service that has them.
* [Loki](https://grafana.com/oss/loki/) - Log aggregation
* [Grafana](https://grafana.com/oss/grafana/) - Visualize and explore metrics, logs and other data.
  * Since we use the [kube-prometheus-stack
](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) helm chart a bunch of dashboards are pre-generated for you. We also automatically deploy dashboards for monitoring rook-ceph.
* [Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/) - Send Prometheus alerts to email, PagerDuty, etc.
* [Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler) - Suggest or automatically adjust resource limits and requests for pods.

## Helm Charts and Terraform Modules Used
* [cert-manager](https://cert-manager.io/docs/installation/kubernetes/#installing-with-helm) v1.3.1
* [metrics-server](https://github.com/helm/charts/tree/master/stable/metrics-server) 2.11.4
* [vpa](https://artifacthub.io/packages/helm/fairwinds-stable/vpa) 0.3.2
* [loki-stack](https://grafana.com/docs/loki/latest/installation/helm/) 2.3.1
* [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) 15.3.1
* [rook-ceph](https://github.com/rook/rook/blob/master/Documentation/helm-operator.md) v1.6.1
* [terraform-kubernetes-metallb](github.com/colinwilson/terraform-kubernetes-metallb) v0.1.6

## Prerequisites and assumptions

This tutorial/repo assumes you have some basic knowledge of computers and networking. It will not walk you through actions
such as installing software, editing files and using a command line interface.

### Hardware

* 4 or more raspberry pi 4 boards (7 minimum recommended).
  * 3 nodes for the control plane, the rest are workers.
  * This tutorial assumes 3 control plane and 4 worker nodes.
  * I used 3x rpi4-4GB for the control plane and 4x rpi4-8GB for the workers.
  * If you have less than 4 worker nodes you may need to tweak the `ceph-block-classes` and `ceph-object-classes` terraform variables.
* microSD cards and power supplies for each rpi.
  * I used 64GB samsung pro endurance microSD cards but any C10/U1 card will do.
* Storage drive attached to each worker node, to be used for Rook-Ceph.
  * I used 128GB USB flash drives for my testing.
  * You'll want to ensure that the drives have no partitions and are using GPT partitioning. This can be done easily from linux:
    * `/usr/sbin/sgdisk --zap-all [DISK_TO_WIPE]`
    * `dd if=/dev/zero of=[DISK_TO_WIPE] bs=1M count=100 oflag=direct,dsync`
* Wired network with access to the internet, including DHCP and DNS.
* A monitor can be useful for getting node IPs during bootstrap, but you can also just scan your network if you feel confident doing so.

### Software

Installed on a PC or raspberry pi that will not be part of the cluster:
* talosctl
* kubectl
* terraform 
  
I recommend using a raspberry pi or other linux system, as we can also use it as a pull-through cache for container images.

### Names and IPs

Various names and network config are mentioned throughout this repo, you can change them as needed.

* Cluster name
  * vanguard
* Network
  * 192.168.57.0/24
  * Gateway: 192.168.57.1
  * DHCP range: 192.168.57.50-99
  * DNS server: 192.168.57.1
* Shared/Virtual IP for Talos/Kubernetes
  * 192.168.57.8
* Control plane nodes:
  * controlplane-0 - 192.168.57.10
  * controlplane-1 - 192.168.57.11
  * controlplane-2 - 192.168.57.12
* Worker nodes:
  * worker-0 - 192.168.57.15
  * worker-1 - 192.168.57.16
  * worker-2 - 192.168.57.17
  * worker-3 - 192.168.57.18
* Storage
  * microSD card for Talos (`/dev/mmcblk0`)
  * USB-based storage for rook-ceph on worker nodes (`/dev/sda`)

## Build a cluster with Talos

Generate cluster config:
```shell
talosctl gen config vanguard https://192.168.57.8:3443 --install-disk /dev/mmcblk0
```

Setup your `~/.talos/config`:

```shell
talosctl --talosconfig=./talosconfig config endpoint 192.168.57.8
```

Create a file for each control plane node from the template [talos/controlplane.yaml](talos/controlplane.yaml), save as `cp#.yaml`.
The various tokens, certs and keys can be found in the `controlplane.yaml` file that `talosctl` generated.

Next, create a file for each control plane node from the template [talos/join.yaml](talos/join.yaml), save as `w#.yaml`.

Apply these configs to your nodes, you will need to change the IPs to match whatever was assigned by DHCP:

```shell
talosctl apply-config --insecure --nodes 192.168.57.50 --file cp0.yaml
talosctl apply-config --insecure --nodes 192.168.57.52 --file cp1.yaml
talosctl apply-config --insecure --nodes 192.168.57.51 --file cp2.yaml
talosctl apply-config --insecure --nodes 192.168.57.56 --file w0.yaml
talosctl apply-config --insecure --nodes 192.168.57.54 --file w1.yaml
talosctl apply-config --insecure --nodes 192.168.57.53 --file w2.yaml
talosctl apply-config --insecure --nodes 192.168.57.55 --file w3.yaml
```

Once controlplane-0 is started you'll be able to bootstrap the cluster:

```shell
talosctl bootstrap --nodes 192.168.57.10 --endpoints 192.168.57.10
```

Have `talosctl` automatically setup your `~/.kube/config` so you can use `kubectl`:

```shell
talosctl kubeconfig --nodes 192.168.57.10
```

The bootstrap process will take some time to complete, wait until all nodes and pods are online and ready. You can monitor
them (once the kubernetes endpoint comes up) with your favorite app (e.g. Lens or k9s) or using `kubectl`:
```shell
  watch "kubectl get nodes -o wide; kubectl get pods -A -o wide;"
  # OR
  kubectl wait nodes --all --for=condition=Ready
  kubectl wait pods --all --all-namespaces --for=condition=Ready
```

## Cluster Services Install

If you would like to monitor etcd, there's an optional step that is needed to make the etcd CA cert available so that
cert-manager can generate client certificates.

Create a `terraform.tfvars` file in the root directory of this repo with the following:

```hcl
etcd-ca = {
  enabled = true
  cert    = ""
  key     = ""
}
```

Be sure to fill in the `cert` and `key` fields with the values from your talos control plane config files. Specifically
the cert and key from the `cluster.etcd.ca` section towards the end of the file.

Because of a chicken-egg problem (with manifests that use CRDs), we have to do a targeted apply first.

```shell
terraform init
terraform apply -parallelism=2 -target=null_resource.init
```

Once the initial targeted apply has completed we can apply the rest of our configuration to the cluster:

```shell
terraform apply -parallelism=2
```

An issue I ran into is that it was surprisingly easy to overload the master nodes and cause etcd to elect a new leader.
When that would happen I had to rerun `terraform apply` since it would crash out. The `-parallelism=2` argument slows things
down and helps prevent the control plane from being overloaded. Additionally, I found that a setting of `-parallelism=1` could
get stuck waiting for resources, after testing `-parallelism=2` seemed to be the most stable for my cluster.
