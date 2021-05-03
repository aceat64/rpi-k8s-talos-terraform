# TODO
* Create a version of this tutorial but using Argo CD instead of Terraform
* Fix the chicken-egg problem, maybe with a provisioner job? Basically the kubernetes_manifest resources that rely on CRDs can't be used until the CRDs exist.
* Stop using kubernetes-alpha and kubectl
* Enhance security
  * Use TLS and cert-based auth for everything that's HTTP and unauthenticated right now
* Ingress controller with Lets Encrypt certs
* SOPS or Sealed Secrets
* Calico?
* Istio?
* Find a way to protect the etcd processes from being overloaded via rate-limits and/or set reservations/limits to ensure other workloads don't impact etcd. 
* Figure out why ceph-mon and ceph-osd livenessProbes fail constantly (RTC/timing issue?)
* Monitor node hardware (e.g. CPU temp)

## Waiting on arm64 images
* Loft
* vertical-pod-autoscaler admissionController
  * There's also a quirk with VPA where it will run a clean-up job that does not have an arm64 image