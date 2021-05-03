resource "helm_release" "metrics-server" {
  repository = "https://charts.helm.sh/stable"
  chart      = "metrics-server"
  version    = var.metrics-server-chart-version
  name       = "metrics-server"
  namespace  = "kube-system"
  wait       = true
  timeout    = 900

  values = [yamlencode({
    image = {
      // The default repository only contains amd64 images
      repository = "k8s.gcr.io/metrics-server/metrics-server"
      tag        = var.metrics-server-image-version
    }

    // Allow metrics-server to run on the control plane
    tolerations = [local.control-plane-toleration]

    // Specify that metrics-server should only run on the control plane
    affinity = {
      nodeAffinity = local.control-plane-node-affinity
    }

    // Create a podDisruptionBudget so that at least 1 pod is always available
    podDisruptionBudget = {
      enabled      = true
      minAvailable = 1
    }

    // Reserve resources for metrics-server, but also limit it so that it can't mess up the control plane
    resources = {
      requests = {
        cpu    = "100m"
        memory = "250Mi"
      }
      limits = {
        cpu    = "250m"
        memory = "512Mi"
      }
    }

    // We want to use the InternalIP for the kubelets
    args = [
      "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
      "--kubelet-use-node-status-port"
    ]
  })]
}