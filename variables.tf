variable "region" {
  default     = "home"
  type        = string
  description = "Used in the ceph-object-storageclass, can be whatever makes sense for your setup."
}

variable "control-plane-nodes" {
  default = [
    "192.168.57.10",
    "192.168.57.11",
    "192.168.57.12",
  ]
  type        = list(string)
  description = "Set to whatever IPs you are using for the control plane nodes."
}

variable "metrics-server-chart-version" {
  default     = "2.11.4"
  type        = string
  description = "Latest can be found using `helm search repo metrics-server` (you'll need the 'stable' repo)"
}

variable "metrics-server-image-version" {
  default     = "v0.4.3"
  type        = string
  description = "Latest can be found at https://github.com/kubernetes-sigs/metrics-server/releases"
}

variable "cert-manager-chart-version" {
  default     = "v1.3.1"
  type        = string
  description = "Latest can be found using `helm search repo cert-manager` (you'll need the jetstack repo)"
}

variable "rook-ceph-chart-version" {
  default     = "v1.6.1"
  type        = string
  description = "Latest can be found at https://github.com/rook/rook/releases"
}

variable "ceph-image-version" {
  default     = "v15.2.11"
  type        = string
  description = <<EOT
  Latest can be found at https://docs.ceph.com/en/latest/releases/octopus/

  NOTE THAT WE USE v15 (Octopus) currently
  EOT
}

variable "prometheus-stack-chart-version" {
  default     = "15.3.1"
  type        = string
  description = "Latest can be found at https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/Chart.yaml"
}

variable "loki-stack-chart-version" {
  default     = "2.3.1"
  type        = string
  description = "Latest can be found using `helm search repo loki-stack` (you'll need the grafana repo)"
}

variable "vpa-chart-version" {
  default = "0.3.2"
  type    = string
}

variable "ceph-block-classes" {
  default = {
    standard = {
      replicated_size   = 2
      target_size_ratio = -1
    }
    durable = {
      replicated_size   = 3
      target_size_ratio = -1
    }
  }
  type = map(object({
    replicated_size   = number
    target_size_ratio = number
  }))
  description = "At a minimum one class called 'standard' needs to be specified."
}

variable "ceph-object-classes" {
  default = {
    standard = {
      replicated_size = 2
      data_chunks     = 3
      coding_chunks   = 1
    }
    durable = {
      replicated_size = 3
      data_chunks     = 2
      coding_chunks   = 2
    }
  }
  type = map(object({
    replicated_size = number
    data_chunks     = number
    coding_chunks   = number
  }))
  description = "At a minimum one class called 'standard' needs to be specified."
}

variable "kubeconfig" {
  default = "~/.kube/config"
  type    = string
}

variable "etcd-ca" {
  default = {
    enabled = false
    cert    = ""
    key     = ""
  }
  type = object({
    enabled = bool
    cert    = string
    key     = string
  })
  description = "Use the values from cluster.etcd.ca exactly as they appear in your controlplane.yaml file."
}