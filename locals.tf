locals {
  // For workloads that need to run on the control plane (master nodes), we have to set a toleration
  control-plane-toleration = {
    key      = "node-role.kubernetes.io/master"
    operator = "Equal"
    effect   = "NoSchedule"
  }
  // Used to specify a workload should only run on the control plane using the node-selector feature
  control-plane-node-selector = {
    "node-role.kubernetes.io/master" = ""
  }
  // Used to specify a workload should only run on the control plane using node affinity
  control-plane-node-affinity = {
    requiredDuringSchedulingIgnoredDuringExecution = {
      nodeSelectorTerms = [{
        matchExpressions = [{
          key      = "node-role.kubernetes.io/master"
          operator = "Exists"
        }]
      }]
    }
  }
}

// This is done so we have a single target to do the initial apply
// We can't run a full apply because some of the manifests we use need CRDs to be installed first before they'll even plan
resource "null_resource" "init" {
  depends_on = [
    helm_release.metrics-server,
    module.metallb,
    helm_release.rook-ceph,
    helm_release.prometheus,
    helm_release.cert-manager
  ]
}