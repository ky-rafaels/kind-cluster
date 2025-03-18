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

# echo "Logging in to cgr in temporary docker client config directory ..."
# # docker login "cgr.dev" --username "b25cd7fccd73dc9a14b3ec891625c5f172624a75/406b943be6f1652d" --password "eyJhbGciOiJSUzI1NiJ9.eyJhdWQiOiJodHRwczovL2lzc3Vlci5lbmZvcmNlLmRldiIsImV4cCI6MTc3MTU5OTE1MCwiaWF0IjoxNzQwMDYzMTUwLCJpc3MiOiJodHRwczovL3B1bGx0b2tlbi5pc3N1ZXIuY2hhaW5ndWFyZC5kZXYiLCJzdWIiOiJwdWxsLXRva2VuLTBjNzhhZDg1ODQzMGYxOTBjYmNkNmZiZTU0M2UzN2Q0OWRlODQ5ZjkifQ.rE9FJ_hLnNFOh4rZdGIFKiNvuI9HtGJQ2Tjllq8HpG7EXm01AwCfDbZaB2gPS-P7I3UnMEZcaTKg3M9odXA7pwFhuvDESiVOgMqpA6wgc2wjS2IkBEkrW7kh_qyujFeguoMAQKOQbFDpupVudhXQV0qZ7nLZK__dhZRyZRKdDHUm1fbPr8xzEBGvhcAerkUX082312hiYgtKEUaNN48d6JSECj2btu4WXYHIhghcy1a-gS69WIu324-9kFRZQ8xiudTKlqvbx1YFAiVQEQdA86UA0xkIxYNO5C4JNK0x1tMNJT2znCfwcEkawUnamDcMWmfZ1kv-uNCnqChYBe0spoclpUPoMTMsR7rO-0_BBex_Q8WQqDbnSJzYXQE4kUm1YKK8SsM494W11PA28Svjj8Cj3rgrr6ZHMw1QTdOgE0yELmJaNtA8CDMX6t_m_o4WjA2VUekOHRpmESQ59Wv6fcslp7SLFNP8lPdw0PU0_9ETsHCGpdFtmgroOA5aJ_GuupT2DR05y5QX_G8xU5IejwsKbZYCbxwekSmcQSFVe5HSojnFAB2Ypm9ePZ854O-XSXDHXkoxRkDemX-71KtnX9FYaz3kNCukzN6ZHNxUjzRhCMiXDsvzCyLWnS8m7I54I57nBByYNjOzX8Kysu"

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
