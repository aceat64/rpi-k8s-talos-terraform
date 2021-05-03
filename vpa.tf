resource "helm_release" "vertical-pod-autoscaler" {
  repository       = "https://charts.fairwinds.com/stable"
  chart            = "vpa"
  version          = var.vpa-chart-version
  name             = "vertical-pod-autoscaler"
  namespace        = "kube-system"
  create_namespace = false
  wait             = true
  timeout          = 900

  values = [yamlencode({
    recommender = {
      extraArgs = {
        // Tell vpa to connect with prometheus so it can make better judgements on resource needs
        prometheus-address = "http://prometheus-kube-prometheus-prometheus.${helm_release.prometheus.namespace}.svc.cluster.local:9090"
        storage            = "prometheus"
      }
    }
    // This helm chart uses an image for the admissionController that doesn't support arm64 yet
    //admissionController = {
    //  enabled = true
    //}
  })]
}