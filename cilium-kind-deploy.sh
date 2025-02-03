#!/usr/bin/env bash
set -o errexit

number=$1
name=$2
region=$3
zone=$4
twodigits=$(printf "%02d\n" $number)
kindest_node=${KINDEST_NODE:-kindest\/node:v1.30.6@sha256:b6d08db72079ba5ae1f4a88a09025c0a904af3b52387643c285442afb05ab994}

if [ -z "$3" ]; then
  region=us-east-1
fi

if [ -z "$4" ]; then
  zone=us-east-1a
fi

# Check if mac or ubuntu
unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Mac;;
esac

# If mac
function is_mac() {
  if hostname -I 2>/dev/null; then
    myip=$(hostname -I | awk '{ print $1 }')
  elif [ -n $(ipconfig getifaddr en0) ]; then
    myip=$(ipconfig getifaddr en0)
  else
    myip=$(ipconfig getifaddr en7)
  fi
}

# If ubuntu
function is_ubuntu() {
    if hostname -I 2>/dev/null; then
      myip=$(hostname -I | awk '{print $1}')
    fi
}

if [ $machine == "Darwin" ]; then
  is_mac
elif [ $machine == "Linux" ]; then
  is_ubuntu
fi

reg_name='kind-registry'
reg_port='5000'
running="$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)"
if [ "${running}" != 'true' ]; then
  docker run \
    -d --restart=always -p "0.0.0.0:${reg_port}:5000" --name "${reg_name}" \
    registry:2
fi

# cache_port='5000'
# cat > registries <<EOF
# docker https://registry-1.docker.io
# us-docker https://us-docker.pkg.dev
# us-central1-docker https://us-central1-docker.pkg.dev
# quay https://quay.io
# gcr https://gcr.io
# EOF

# cat registries | while read cache_name cache_url; do
running="$(docker inspect -f '{{.State.Running}}' "${cache_name}" 2>/dev/null || true)"
if [ "${running}" != 'true' ]; then
  cat > ${HOME}/.${cache_name}-config.yml <<EOF
version: 0.1
proxy:
  remoteurl: ${cache_url}
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF

  docker run \
    -d --restart=always -v ${HOME}/.${cache_name}-config.yml:/etc/docker/registry/config.yml --name "${cache_name}" \
    registry:2
fi
# done

cat << EOF > kind${number}.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: ${kindest_node}
  extraPortMappings:
  - containerPort: 6443
    hostPort: 70${twodigits}
- role: worker
  image: ${kindest_node}
  extraMounts:
  - hostPath: ./shared-storage
    containerPath: /var/local-path-provisioner
- role: worker
  image: ${kindest_node}
  extraMounts:
  - hostPath: ./shared-storage
    containerPath: /var/local-path-provisioner
networking:
  disableDefaultCNI: true
  kubeProxyMode: none
  serviceSubnet: "10.$(echo $twodigits | sed 's/^0*//').0.0/16"
  podSubnet: "10.1${twodigits}.0.0/16"
kubeadmConfigPatches:
- |
  kind: InitConfiguration
  nodeRegistration:
    kubeletExtraArgs:
      node-labels: "ingress-ready=true,topology.kubernetes.io/region=${region},topology.kubernetes.io/zone=${zone}"
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry]
    config_path = "/etc/containerd/certs.d"
EOF

REGISTRY_DIR="/etc/containerd/certs.d/localhost:${reg_port}"
for node in $(kind get nodes); do
  docker exec "${node}" mkdir -p "${REGISTRY_DIR}"
  cat <<EOF | docker exec -i "${node}" cp /dev/stdin "${REGISTRY_DIR}/hosts.toml"
[host."http://${reg_name}:5000"]
EOF
done

kind create cluster --name kind${number} --config kind${number}.yaml

ipkind=$(docker inspect kind${number}-control-plane | jq -r '.[0].NetworkSettings.Networks[].IPAddress')
networkkind=$(echo ${ipkind} | awk -F. '{ print $1"."$2 }')

kubectl config set-cluster kind-kind${number} --server=https://${myip}:70${twodigits} --insecure-skip-tls-verify=true

helm repo add cilium https://helm.cilium.io/

helm --kube-context kind-kind${number} install cilium cilium/cilium --version 1.16.3 \
   --namespace kube-system \
   --set prometheus.enabled=true \
   --set operator.prometheus.enabled=true \
   --set k8sServiceHost=kind${number}-control-plane \
   --set k8sServicePort=6443 \
   --set hubble.enabled=true \
   --set hubble.metrics.enabled="{dns:destinationContext=pod|ip;sourceContext=pod|ip,drop:destinationContext=pod|ip;sourceContext=pod|ip,tcp:destinationContext=pod|ip;sourceContext=pod|ip,flow:destinationContext=pod|ip;sourceContext=pod|ip,port-distribution:destinationContext=pod|ip;sourceContext=pod|ip}" \
   --set hubble.relay.enabled=true \
   --set hubble.ui.enabled=true \
   --set kubeProxyReplacement=true \
   --set hostServices.enabled=false \
   --set hostServices.protocols="tcp" \
   --set socketLB.hostNamespaceOnly=true \
   --set externalIPs.enabled=true \
   --set nodePort.enabled=true \
   --set hostPort.enabled=true \
   --set ipv4NativeRoutingCIDR="10.1${twodigits}.0.0/16" \
   --set routingMode=native \
   --set bpf.masquerade=true \
   --set autoDirectNodeRoutes=true \
   --set image.pullPolicy=IfNotPresent \
   --set ipam.mode=kubernetes
kubectl --context=kind-kind${number} -n kube-system rollout status ds cilium || true

docker network connect "kind" "${reg_name}" || true
# docker network connect "kind" docker || true
# docker network connect "kind" us-docker || true
# docker network connect "kind" us-central1-docker || true
# docker network connect "kind" quay || true
# docker network connect "kind" gcr || true

# Preload MetalLB images
docker pull quay.io/metallb/controller:v0.13.12
docker pull quay.io/metallb/speaker:v0.13.12
# Make a tmp dir, could deprecate this step in the future
mkdir -p $HOME/tmp
TMPDIR=$HOME/tmp kind load docker-image quay.io/metallb/controller:v0.13.12 --name kind${number}
TMPDIR=$HOME/tmp kind load docker-image quay.io/metallb/speaker:v0.13.12 --name kind${number}
kubectl --context=kind-kind${number} apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
kubectl --context=kind-kind${number} create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
kubectl --context=kind-kind${number} -n metallb-system rollout status deploy controller || true

cat << EOF > metallb${number}.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - ${networkkind}.1${twodigits}.1-${networkkind}.1${twodigits}.254
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: empty
  namespace: metallb-system
EOF

printf "Create IPAddressPool in kind-kind${number}\n"
for i in {1..10}; do
kubectl --context=kind-kind${number} apply -f metallb${number}.yaml && break
sleep 2
done

# connect the registry to the cluster network if not already connected
printf "Renaming context kind-kind${number} to ${name}\n"
for i in {1..100}; do
  (kubectl config get-contexts -oname | grep ${name}) && break
  kubectl config rename-context kind-kind${number} ${name} && break
  printf " $i"/100
  sleep 2
  [ $i -lt 100 ] || exit 1
done

# Document the local registry
# https://github.com/kubernetes/enhancements/tree/master/keps/sig-cluster-lifecycle/generic/1755-communicating-a-local-registry
cat <<EOF | kubectl --context=${name} apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${reg_port}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
