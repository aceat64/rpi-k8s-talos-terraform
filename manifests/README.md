# Useful Manifests
This folder contains manifest files that can be useful for various maintenance actions.

## zapper.yaml
WARNING! This manifest will create a daemonset so that pods will be created on every node and wipe the `/dev/sda` drive.
This is needed if you had rook-ceph setup (partially or fully) and are redoing the cluster.