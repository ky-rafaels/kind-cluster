# KinD Cilium Cluster

Deploys a KinD cluster using cilium as CNI. Also mounts a local `./shared-storage` directory used for persistence. MetalLB installation for loadbalancer routing.

## Dependencies

- [kind](https://kind.sigs.k8s.io/)
- helm
- kubectl
- docker OR [podman w/ docker plugin](https://podman-desktop.io/docs/migrating-from-docker/managing-docker-compatibility)

## Running

Feed in commandline args like below

Example:
```bash
./cilium-kind-deploy.sh 1 cluster1

or 

# Label nodes wih your own AWS labels
./cilium-kind-deploy.sh 2 mgmt us-east-1 us-east-1a

```

## Using Mac

If using Mac, consider installing [docker-mac-net-connect](https://github.com/chipmk/docker-mac-net-connect) for use in hitting frontend services from local browser.