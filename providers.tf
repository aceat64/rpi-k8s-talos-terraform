// For simplicity we just use the kubeconfig file to get credentials for talking to the kubernetes cluster.
// If you have some other method for authenticating with the cluster you can change these provider entries as needed.

provider "kubernetes" {
  config_path = var.kubeconfig
}

provider "kubernetes-alpha" {
  config_path = var.kubeconfig
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig
  }
}

provider "kubectl" {
  config_path = var.kubeconfig
}