# Kubernetes scheduling demo with kind

This lab defines a four-node kind cluster and five small application components
for demonstrating:

- node taints and pod tolerations
- required node affinity
- required pod affinity
- required pod anti-affinity
- service-to-service communication
- ConfigMap-mounted application configuration

Nothing in this repository creates or changes a cluster automatically. Run the
commands below when you are ready to perform the lab.

## Demo architecture

The kind cluster contains one control-plane node and three workers:

| Worker role | Labels | Taint | Intended workloads |
| --- | --- | --- | --- |
| edge | `demo-role=edge`, `demo-workload=apps` | none | gateway, catalog, orders |
| general | `demo-role=general`, `demo-workload=apps` | none | catalog, orders |
| restricted | `demo-role=restricted` | `dedicated=payments:NoSchedule` | payments only |

The application contains five components:

1. `gateway`: nginx frontend configured by the `gateway-config` ConfigMap.
2. `catalog`: two HTTP echo replicas spread across app workers.
3. `orders`: two HTTP echo replicas placed with catalog but apart from each other.
4. `payments`: HTTP echo service placed on the dedicated worker.
5. `traffic-generator`: repeatedly calls the gateway and catalog to produce
   observable service-to-service traffic.

Traffic paths:

```text
traffic-generator --> gateway --> catalog
                            |----> orders
                            `----> payments
traffic-generator -------------> catalog
```

## Files

- `kind-config.yaml`: four-node cluster, worker labels, and the payments taint.
- `kubernetes/demo.yaml`: namespace, ConfigMap, Services, and Deployments.

## Prerequisites

- Docker
- kind
- kubectl

## Create and deploy

Create the cluster:

```bash
kind create cluster --config kind-config.yaml
```

Confirm the node labels and taints:

```bash
kubectl get nodes -L demo-role,demo-workload
kubectl describe node scheduling-demo-worker3
```

Apply the demo:

```bash
kubectl apply -f kubernetes/demo.yaml
kubectl wait --for=condition=Available deployment --all \
  -n scheduling-demo --timeout=180s
kubectl get pods -n scheduling-demo -o wide
```

Expected placement:

- both `gateway` pods run on the edge worker because of node affinity
- `catalog` replicas run on different app workers because of pod anti-affinity
- `orders` replicas run where catalog runs, but apart from each other
- `payments` runs on the restricted worker because it has both the required
  node affinity and matching toleration
- `traffic-generator` runs with a gateway pod because of pod affinity

## Observe microservice traffic

Follow the generated requests:

```bash
kubectl logs -n scheduling-demo \
  deployment/traffic-generator --follow
```

Call the gateway manually from inside the cluster:

```bash
kubectl run curl-demo -n scheduling-demo --rm -it --restart=Never \
  --image=curlimages/curl:8.10.1 -- \
  curl -s http://gateway/catalog
```

Inspect the nginx configuration mounted from the ConfigMap:

```bash
kubectl get configmap gateway-config -n scheduling-demo -o yaml
kubectl exec -n scheduling-demo deployment/gateway -- \
  cat /etc/nginx/conf.d/default.conf
```

## Demo 1: taint without a toleration

The restricted worker rejects ordinary pods:

```bash
kubectl run no-toleration -n scheduling-demo \
  --image=nginx:1.27-alpine \
  --overrides='
{
  "spec": {
    "nodeSelector": {
      "demo-role": "restricted"
    }
  }
}'
```

The pod remains `Pending`. The scheduler event explains that the node has an
untolerated taint:

```bash
kubectl describe pod no-toleration -n scheduling-demo
```

Compare it with the payments pod, whose manifest includes:

```yaml
tolerations:
  - key: dedicated
    operator: Equal
    value: payments
    effect: NoSchedule
```

Clean up the intentionally pending pod:

```bash
kubectl delete pod no-toleration -n scheduling-demo
```

## Demo 2: toleration permits, affinity selects

A toleration does not force a pod onto a tainted node; it only makes that node
eligible. `payments` combines a matching toleration with required node affinity
to select the restricted worker.

Display both rules and the selected node:

```bash
kubectl get deployment payments -n scheduling-demo \
  -o jsonpath='{.spec.template.spec.tolerations}{"\n"}{.spec.template.spec.affinity}{"\n"}'
kubectl get pods -n scheduling-demo -l app=payments -o wide
```

## Demo 3: pod anti-affinity

The catalog replicas use required pod anti-affinity with
`kubernetes.io/hostname` as the topology key:

```bash
kubectl get pods -n scheduling-demo -l app=catalog \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
```

There are only two workers labelled `demo-workload=apps`. Scaling catalog to
three replicas intentionally leaves the third replica pending:

```bash
kubectl scale deployment catalog -n scheduling-demo --replicas=3
kubectl get pods -n scheduling-demo -l app=catalog -o wide
kubectl get events -n scheduling-demo \
  --field-selector reason=FailedScheduling --sort-by=.lastTimestamp
```

Restore the declared state:

```bash
kubectl apply -f kubernetes/demo.yaml
```

## Demo 4: pod affinity

Orders has required pod affinity toward catalog. Each orders pod must run in a
hostname topology that already contains a catalog pod. Orders also has
anti-affinity toward other orders replicas.

Compare placement:

```bash
kubectl get pods -n scheduling-demo \
  -l 'app in (catalog,orders)' \
  -o custom-columns=APP:.metadata.labels.app,NAME:.metadata.name,NODE:.spec.nodeName
```

The traffic generator similarly follows the gateway onto the edge worker.

## Demo 5: break and restore node affinity

Remove the edge label to make replacement gateway pods unschedulable:

```bash
kubectl label node scheduling-demo-worker demo-role-
kubectl delete pod -n scheduling-demo -l app=gateway
kubectl get pods -n scheduling-demo -l app=gateway -o wide
kubectl get events -n scheduling-demo \
  --field-selector reason=FailedScheduling --sort-by=.lastTimestamp
```

Restore the label:

```bash
kubectl label node scheduling-demo-worker demo-role=edge
kubectl wait --for=condition=Available deployment/gateway \
  -n scheduling-demo --timeout=120s
```

## Cleanup

Delete only the demo workloads:

```bash
kubectl delete -f kubernetes/demo.yaml
```

Delete the complete kind cluster:

```bash
kind delete cluster --name scheduling-demo
```
