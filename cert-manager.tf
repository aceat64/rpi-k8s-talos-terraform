resource "kubernetes_namespace" "cert-manager" {
  metadata {
    name = "cert-manager"
  }
}

resource "helm_release" "cert-manager" {
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert-manager-chart-version
  name             = "cert-manager"
  namespace        = kubernetes_namespace.cert-manager.metadata.0.name
  create_namespace = false
  wait             = true
  timeout          = 900

  set {
    name  = "installCRDs"
    value = true
  }
}