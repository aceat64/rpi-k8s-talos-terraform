module "metallb" {
  source = "github.com/colinwilson/terraform-kubernetes-metallb?ref=0.1.6"

  // We want the MetalLB controller running on the control plane
  controller_toleration    = [local.control-plane-toleration]
  controller_node_selector = local.control-plane-node-selector
}

resource "kubernetes_config_map" "metallb_config" {
  metadata {
    name      = "config"
    namespace = "metallb-system"
  }

  // Change this to fit your needs!
  data = {
    config = yamlencode({
      address-pools = [
        {
          name      = "default"
          protocol  = "layer2"
          addresses = ["192.168.57.100-192.168.57.254"]
        }
      ]
    })
  }

  // This is required because the module creates the metallb-system namespace
  depends_on = [module.metallb]
}