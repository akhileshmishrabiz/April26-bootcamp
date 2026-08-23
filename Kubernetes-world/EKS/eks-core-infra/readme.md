# EKS Core infra

- vpc, subnets and all about that
- eks infra and related stuff like iam roles for node 
- add on (vpc cni, csi and many more)


# force delete the secrets without recovery 


aws secretsmanager delete-secret --secret-id db/devopsdozo-db --force-delete-without-recovery



curl -X POST http://localhost:3223/api/topics \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Docker",
    "description": "Learn Docker containerization",
    "slug": "docker"
  }'