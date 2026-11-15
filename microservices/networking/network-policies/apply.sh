#!/usr/bin/env bash
# Apply the ecommerce network policies.
# The deploy script does not call this. Run it when you want the lockdown.
#
#   ./network-policies/apply.sh
#   ./network-policies/apply.sh 90-default-deny.yaml
#
# Policies are unioned. An egress policy on a pod drops every other egress
# path, so apply the whole directory rather than a single allow file.
# Remove them with: kubectl delete -f network-policies

set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! kubectl get namespace ecommerce >/dev/null 2>&1; then
    echo "Namespace ecommerce does not exist. Deploy the app first." >&2
    exit 1
fi

if [[ $# -eq 0 ]]; then
    echo "Applying all policies in ${DIR} (default-deny last)..."
    for manifest in \
        10-allow-dns.yaml \
        20-allow-kube-apiserver.yaml \
        30-allow-external-and-probes.yaml \
        40-api-gateway.yaml \
        50-service-dependencies.yaml \
        60-seed-and-observability.yaml \
        90-default-deny.yaml
    do
        kubectl apply -f "${DIR}/${manifest}"
    done
else
    for manifest in "$@"; do
        if [[ "${manifest}" != /* ]]; then
            manifest="${DIR}/${manifest}"
        fi
        kubectl apply -f "${manifest}"
    done
fi

echo ""
echo "Policies applied in namespace ecommerce."
echo "Test from a pod, not from the Kind node (node traffic is allowed for probes)."
echo "cart-service is Node and has no wget; use fetch with a short timeout:"
echo "  kubectl -n ecommerce exec deploy/cart-service -- node -e \"fetch('http://product-service:8001/health',{signal:AbortSignal.timeout(3000)}).then(r=>r.text()).then(console.log)\""
echo "  kubectl -n ecommerce exec deploy/cart-service -- node -e \"fetch('http://user-service:8002/health',{signal:AbortSignal.timeout(3000)}).then(r=>r.text()).then(console.log)\""
echo "The first call is allowed. The second should fail with TimeoutError."
echo ""
echo "Remove the policies:"
echo "  kubectl delete -f ${DIR}"
