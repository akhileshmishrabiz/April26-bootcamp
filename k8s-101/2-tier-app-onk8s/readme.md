# rds postgres -> note down the creds
# keep rds public for testing and delete afterwards

# find way to pass db_link to the cluster


# rds 

```bash
aws rds create-db-instance \
  --db-instance-identifier tiny-pg \
  --db-instance-class db.t4g.micro \
  --engine postgres \
  --engine-version 16.10 \
  --master-username pgadmin \
  --master-user-password 'ChangeMe123!' \
  --allocated-storage 20 \
  --db-name mydb \
  --publicly-accessible \
  --backup-retention-period 0 \
  --no-multi-az
```

```bash
DB_LINK=postgresql://pgadmin:ChangeMe123!@tiny-pg.cvik8accw2tk.ap-south-1.rds.amazonaws.com:5432/mydb
```

ecr: 879381241087.dkr.ecr.ap-south-1.amazonaws.com/2-tierapp

```bash 
docker build --platform linux/amd64 -t 879381241087.dkr.ecr.ap-south-1.amazonaws.com/2-tierapp:1.0 .

aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin 879381241087.dkr.ecr.ap-south-1.amazonaws.com

docker push 879381241087.dkr.ecr.ap-south-1.amazonaws.com/2-tierapp:1.0

```

# k8s image pull secret
```bash
kubectl create secret docker-registry ecr-secret \
  --docker-server=879381241087.dkr.ecr.ap-south-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-south-1)
```
