// Currently disabled because there are no arm64 images available yet
//resource "kubernetes_namespace" "loft" {
//  metadata {
//    name = "loft"
//  }
//}
//
//resource "helm_release" "loft" {
//  repository       = "https://charts.devspace.sh/"
//  chart            = "loft"
//  version          = "1.10.1"
//  name             = "loft"
//  namespace        = kubernetes_namespace.loft.metadata.0.name
//  create_namespace = false
//  wait             = true
//  timeout          = 900
//
//  values = [yamlencode({
//    serviceMonitor = {
//      enabled = true
//    }
//  })]
//}