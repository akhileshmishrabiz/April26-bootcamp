879381241087.dkr.ecr.ap-south-1.amazonaws.com/augk8s26-backend:dafc1c583ef1f4fb2836569cc7f87ce1063b7cc4

879381241087.dkr.ecr.ap-south-1.amazonaws.com/augk8s26-frontend:dafc1c583ef1f4fb2836569cc7f87ce1063b7cc4


```bash

kubectl run dns-test --rm -it \
  --image=busybox:1.36 \
  --restart=Never \
  -- nslookup backend-service.devopsdozo.svc.cluster.local
```


```bash

kubectl run dns-test --rm -it \
  --image=busybox:1.36 \
  --restart=Never \
  -- nslookup 172.20.149.129
```


```bash
kubectl run postgres-test \
  --rm -it \
  --image=postgres:16 \
  --restart=Never \
  --env="DATABASE_URL=postgresql://postgres:UiQ94pjLUO@devopsdozo.cvik8accw2tk.ap-south-1.rds.amazonaws.com:5432/devopsdozodb" \
  -- bash -c 'psql "$DATABASE_URL" -c "SELECT 1;"'
```