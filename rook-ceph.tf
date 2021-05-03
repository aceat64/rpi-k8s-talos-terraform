resource "kubernetes_namespace" "rook-ceph" {
  metadata {
    name = "rook-ceph"
  }
}

resource "helm_release" "rook-ceph" {
  repository       = "https://charts.rook.io/release"
  chart            = "rook-ceph"
  version          = var.rook-ceph-chart-version
  name             = "rook-ceph"
  namespace        = kubernetes_namespace.rook-ceph.metadata.0.name
  create_namespace = false
  wait             = true
  timeout          = 900

  values = [yamlencode({
    // Set requests and limits for the rook-ceph operator
    resources = {
      limits = {
        cpu    = "2000m"
        memory = "512Mi"
      }
      requests = {
        cpu    = "250m"
        memory = "256Mi"
      }
    }

    // Disabled because I don't plan on using them currently
    csi = {
      enableCephfsSnapshotter = false
      enableRBDSnapshotter    = false
    }
  })]
}

// Create the ceph cluster! This might take a while...
resource "kubernetes_manifest" "ceph-cluster" {
  provider = kubernetes-alpha
  wait_for = {
    fields = {
      // We'll wait until the cluster is ready
      "status.phase" = "Ready"
    }
  }

  manifest = {
    apiVersion = "ceph.rook.io/v1"
    kind       = "CephCluster"
    metadata = {
      name      = helm_release.rook-ceph.name
      namespace = helm_release.rook-ceph.namespace
    }
    spec = {
      cephVersion = {
        image = "ceph/ceph:${var.ceph-image-version}"
      }

      dataDirHostPath                   = "/var/lib/rook"
      waitTimeoutForHealthyOSDInMinutes = 10

      mon = {
        count = 3
      }

      mgr = {
        count = 1
        modules = [
          {
            enabled = true
            name    = "pg_autoscaler"
          }
        ]
      }

      // We could probably do without this dashboard since we have Grafana, but you might want to poke around it
      dashboard = {
        enabled = true
        ssl     = true
      }

      // Enable metrics and alerting rules
      monitoring = {
        enabled        = true
        rulesNamespace = helm_release.rook-ceph.namespace
      }

      // Disabled to save on resources
      crashCollector = {
        disable = true
      }

      resources = {
        // Set requests and limits for various rook-ceph workloads
        mgr = {
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
        }
        mon = {
          limits = {
            cpu    = "1"
            memory = "2Gi"
          }
          requests = {
            cpu    = "250m"
            memory = "768Mi"
          }
        }
        osd = {
          limits = {
            cpu    = "1"
            memory = "2Gi"
          }
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
        }
      }

      storage = {
        useAllDevices = true
        useAllNodes   = true
      }

      disruptionManagement = {
        managePodBudgets = true
      }

      healthCheck = {
        daemonHealth = {
          mon    = {}
          osd    = {}
          status = {}
        }

        // These liveness probes fail constantly and cause the pods to restart
        livenessProbe = {
          mon = {
            disabled = true
          }
          osd = {
            disabled = true
          }
        }
      }
    }
  }
}

// Create the CephBlockPools for our block storage, this creates a manifest for each class specified in var.ceph-block-classes
resource "kubernetes_manifest" "ceph-block-pool" {
  provider = kubernetes-alpha
  for_each = var.ceph-block-classes

  manifest = {
    apiVersion = "ceph.rook.io/v1"
    kind       = "CephBlockPool"
    metadata = {
      name      = "${each.key}-pool"
      namespace = helm_release.rook-ceph.namespace
    }

    spec = {
      failureDomain = "host"
      replicated = {
        size                   = each.value["replicated_size"]
        requireSafeReplicaSize = each.value["replicated_size"] == 1 ? false : true
        // gives a hint (%) to Ceph in terms of expected consumption of the total cluster capacity of a given pool
        //targetSizeRatio = each.value["target_size_ratio"] < 0 ? null : each.value["target_size_ratio"]
      }
    }
  }

  depends_on = [kubernetes_manifest.ceph-cluster]
}

// Create a StorageClass for each class specified in var.ceph-block-classes
resource "kubernetes_manifest" "ceph-storageclass" {
  provider = kubernetes-alpha
  for_each = var.ceph-block-classes

  manifest = {
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = "${each.key}-block"
    }

    provisioner = "${helm_release.rook-ceph.namespace}.rbd.csi.ceph.com"

    parameters = {
      clusterID     = helm_release.rook-ceph.name
      pool          = kubernetes_manifest.ceph-block-pool[each.key].manifest.metadata.name
      imageFormat   = 2
      imageFeatures = "layering"

      "csi.storage.k8s.io/fstype" = "ext4"

      "csi.storage.k8s.io/provisioner-secret-name"            = "rook-csi-rbd-provisioner"
      "csi.storage.k8s.io/provisioner-secret-namespace"       = helm_release.rook-ceph.namespace
      "csi.storage.k8s.io/controller-expand-secret-name"      = "rook-csi-rbd-provisioner"
      "csi.storage.k8s.io/controller-expand-secret-namespace" = helm_release.rook-ceph.namespace
      "csi.storage.k8s.io/node-stage-secret-name"             = "rook-csi-rbd-node"
      "csi.storage.k8s.io/node-stage-secret-namespace"        = helm_release.rook-ceph.namespace
    }

    allowVolumeExpansion = true
    reclaimPolicy        = "Delete"
  }

  depends_on = [kubernetes_manifest.ceph-block-pool]
}

// Create the CephObjectStores for our object storage, this creates a manifest for each class specified in var.ceph-object-classes
resource "kubernetes_manifest" "ceph-object-storage" {
  provider = kubernetes-alpha
  for_each = var.ceph-object-classes

  manifest = {
    apiVersion = "ceph.rook.io/v1"
    kind       = "CephObjectStore"
    metadata = {
      name      = "${each.key}-object"
      namespace = helm_release.rook-ceph.namespace
    }

    spec = {
      metadataPool = {
        failureDomain = "host"
        replicated = {
          size = each.value["replicated_size"]
        }
      }

      dataPool = {
        failureDomain = "host"
        replicated = {
          size = each.value["replicated_size"]
        }
        // Erasure Coded storage doesn't yet work (as of 1.6.0/15.2.10) because the CRDs require replicated.size to be >0
        //erasureCoded = {
        //  dataChunks   = each.value["data_chunks"]
        //  codingChunks = each.value["coding_chunks"]
        //}
      }

      preservePoolsOnDelete = true

      gateway = {
        port      = 80
        instances = 1
        placement = {}
        resources = {}
      }
    }
  }

  depends_on = [kubernetes_manifest.ceph-cluster]
}

// Create a StorageClass for each class specified in var.ceph-object-classes
resource "kubernetes_manifest" "ceph-object-storageclass" {
  provider = kubernetes-alpha
  for_each = var.ceph-object-classes

  manifest = {
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = "${each.key}-bucket"
    }

    provisioner   = "${helm_release.rook-ceph.namespace}.rbd.csi.ceph.com"
    reclaimPolicy = "Delete"

    parameters = {
      objectStoreName      = "${each.key}-object"
      objectStoreNamespace = helm_release.rook-ceph.namespace
      region               = var.region
    }
  }

  depends_on = [kubernetes_manifest.ceph-object-storage]
}

// Download a bunch of prometheus rules for ceph
data "http" "ceph-prometheus-rules" {
  url = "https://raw.githubusercontent.com/rook/rook/${var.rook-ceph-chart-version}/cluster/examples/kubernetes/ceph/monitoring/prometheus-ceph-v14-rules.yaml"
}

// Apply the downloaded manifests
resource "kubectl_manifest" "ceph-prometheus-rules" {
  yaml_body  = data.http.ceph-prometheus-rules.body
  depends_on = [helm_release.prometheus]
}

// Create dashboards for ceph
resource "kubernetes_config_map" "grafana-dashboards-ceph" {
  metadata {
    name      = "grafana-dashboard-ceph"
    namespace = kubernetes_namespace.prometheus.metadata[0].name
    labels = {
      // This is the label that Grafana looks for when searching for dashboard configs
      grafana_dashboard = 1
    }
    annotations = {
      // This tells Grafana where in it's pod to place the dashboards
      k8s-sidecar-target-directory = "/tmp/dashboards/ceph"
    }
  }

  data = {
    // Slightly modified from: https://grafana.com/dashboards/2842
    "ceph-cluster-dashboard.json" = file("grafana-dashboards/ceph-cluster-dashboard.json")

    // Slightly modified from: https://grafana.com/dashboards/5336
    "ceph-osd-single-dashboard.json" = file("grafana-dashboards/ceph-osd-single-dashboard.json")

    // Slightly modified from: https://grafana.com/dashboards/5342
    "ceph-pools-dashboard.json" = file("grafana-dashboards/ceph-pools-dashboard.json")
  }
}