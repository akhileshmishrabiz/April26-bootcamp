# EKS cluster 

#Dev env
```bash
terraform init -backend-config=vars/dev.tfbackend
terraform plan -var-file=vars/dev.tfvars
``


#prod env
```bash
terraform init -backend-config=vars/prod.tfbackend
terraform apply -var-file=vars/prod.tfvars
``