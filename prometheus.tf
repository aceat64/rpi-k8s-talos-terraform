resource "kubernetes_namespace" "prometheus" {
  metadata {
    name = "prometheus"
  }
}

resource "helm_release" "prometheus" {
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.prometheus-stack-chart-version
  name             = "prometheus"
  namespace        = kubernetes_namespace.prometheus.metadata.0.name
  create_namespace = false
  wait             = false

  values = [yamlencode({
    alertmanager = {
      alertmanagerSpec = {
        // Create a 10GiB volume for alertmanager
        storage = {
          volumeClaimTemplate = {
            spec = {
              accessModes = ["ReadWriteOnce"]
              resources = {
                requests = {
                  storage = "10Gi"
                }
              }
              storageClassName = "standard-block"
            }
          }
        }
      }

      // Make alertmanager available via a loadbalancer
      service = {
        type = "LoadBalancer"
      }
    }

    grafana = {
      // Enable persistence using Persistent Volume Claims
      persistence = {
        enabled          = true
        storageClassName = "standard-block"
      }

      // Make Grafana available via a loadbalancer
      service = {
        type = "LoadBalancer"
      }

      additionalDataSources = [
        {
          // Automatically add Loki as a datasource to Grafana
          name     = "Loki"
          type     = "loki"
          access   = "proxy"
          orgId    = 1
          url      = "http://loki.loki.svc.cluster.local:3100/"
          version  = 1
          editable = false
        }
      ]
    }

    // This serviceMonitor is enabled by default, but let's add a selector so it works a bit better
    kubeControllerManager = {
      service = {
        selector = {
          k8s-app = "kube-controller-manager"
        }
      }
    }

    // Since etcd isn't running inside the cluster, we have to tell Prometheus to use the control plane node IPs directly
    kubeEtcd = {
      enabled   = var.etcd-ca.enabled
      endpoints = var.control-plane-nodes
      serviceMonitor = {
        scheme   = "https"
        caFile   = "/etc/prometheus/secrets/etcd-client-cert/ca.crt"
        certFile = "/etc/prometheus/secrets/etcd-client-cert/tls.crt"
        keyFile  = "/etc/prometheus/secrets/etcd-client-cert/tls.key"
      }
    }

    // This is also enabled by default, but the selector makes things work a bit better
    kubeProxy = {
      service = {
        selector = {
          k8s-app = "kube-proxy"
        }
      }
    }

    // This is also enabled by default, but the selector makes things work a bit better
    kubeScheduler = {
      service = {
        selector = {
          k8s-app = "kube-scheduler"
        }
      }
    }

    prometheus = {
      prometheusSpec = {
        // By unsetting these selectors Prometheus will check cluster-wide for monitors and rules
        ruleSelectorNilUsesHelmValues           = false
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        probeSelectorNilUsesHelmValues          = false

        // Create a 10GiB volume for prometheus
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              accessModes = ["ReadWriteOnce"]
              resources = {
                requests = {
                  storage = "10Gi"
                }
              }
              storageClassName = "standard-block"
            }
          }
        }

        // We need to make sure the etcd-client-cert secret is added to the pod (if etcd monitoring is enabled)
        secrets = var.etcd-ca.enabled ? ["etcd-client-cert"] : null
      }

      // Make prometheus available via a loadbalancer
      service = {
        type = "LoadBalancer"
      }
    }
  })]

  depends_on = [helm_release.rook-ceph]
}

// Create a secret with the CA cert and key for etcd, so that we can generate client certs for scraping metrics
resource "kubernetes_secret" "etcd-ca-key-pair" {
  count = var.etcd-ca.enabled ? 1 : 0
  metadata {
    name      = "etcd-ca-key-pair"
    namespace = kubernetes_namespace.prometheus.metadata.0.name
  }
  data = {
    "tls.crt" = base64decode(var.etcd-ca.cert)
    "tls.key" = base64decode(var.etcd-ca.key)
  }
}

// Create the cert-manager Issuer that will sign client certs using the etcd CA key
resource "kubernetes_manifest" "etcd-ca-issuer" {
  count    = var.etcd-ca.enabled ? 1 : 0
  provider = kubernetes-alpha
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "etcd-ca-issuer"
      namespace = kubernetes_namespace.prometheus.metadata.0.name
    }
    spec = {
      ca = {
        secretName = kubernetes_secret.etcd-ca-key-pair[0].metadata.0.name
      }
    }
  }
}

// Generate a client cert for scraping etcd metrics
resource "kubernetes_manifest" "etcd-client-cert" {
  count    = var.etcd-ca.enabled ? 1 : 0
  provider = kubernetes-alpha
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "etcd-client-cert"
      namespace = kubernetes_namespace.prometheus.metadata.0.name
    }
    spec = {
      secretName  = "etcd-client-cert"
      duration    = "2160h0m0s" # 90d
      renewBefore = "720h0m0s"  # 30d
      subject = {
        organizations = [
          "prometheus"
        ]
      }
      privateKey = {
        algorithm = "ECDSA"
        size      = 256
      }
      usages = [
        "client auth"
      ]
      ipAddresses = [
        "127.0.0.1"
      ]
      issuerRef = {
        name = kubernetes_manifest.etcd-ca-issuer[0].manifest.metadata.name
        kind = kubernetes_manifest.etcd-ca-issuer[0].manifest.kind
      }
    }
  }
}