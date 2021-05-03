resource "kubernetes_namespace" "loki" {
  metadata {
    name = "loki"
  }
}

resource "helm_release" "loki" {
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki-stack"
  version          = var.loki-stack-chart-version
  name             = "loki"
  namespace        = kubernetes_namespace.loki.metadata.0.name
  create_namespace = false
  wait             = true
  timeout          = 900
}