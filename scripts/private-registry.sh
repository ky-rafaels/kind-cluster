#!/bin/sh
set -o errexit

# desired cluster name; default is "kind"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind2}"

# # create a temp file for the docker config
# echo "Creating temporary docker client config directory ..."
# DOCKER_CONFIG=$(mktemp -d)
# export DOCKER_CONFIG
# trap 'echo "Removing ${DOCKER_CONFIG}/*" && rm -rf ${DOCKER_CONFIG:?}' EXIT

# echo "Creating a temporary config.json"

# # chainctl auth configure-docker --pull-token --save
# cat <<EOF >"${DOCKER_CONFIG}/config.json"
# {
#  "auths": { "cgr.dev": {} }
# }
# EOF

# chainctl auth configure-docker --pull-token --save
DOCKER_CONFIG=~/.docker
# setup credentials on each node
echo "Moving credentials to kind cluster name='${KIND_CLUSTER_NAME}' nodes ..."
for node in $(kind get nodes --name "${KIND_CLUSTER_NAME}"); do
  # the -oname format is kind/name (so node/name) we just want name
  node_name=${node#node/}
  # copy the config to where kubelet will look
  docker cp "${DOCKER_CONFIG}/config.json" "${node_name}:/var/lib/kubelet/config.json"
  # restart kubelet to pick up the config
  docker exec "${node_name}" systemctl restart kubelet.service
done

echo "Done!"
