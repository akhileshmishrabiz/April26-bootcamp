aws s3api list-object-versions \
  --bucket state-bucket-879381241087 \
  --prefix april26/ecs/terraform.tfstate


aws s3api copy-object \
  --bucket state-bucket-879381241087 \
  --copy-source "april26/ecs/terraform.tfstate?versionId=k88bMlm6iUuuU7xS2nJmlpefKEd7zZus" \
  --key april26/ecs/terraform.tfstate


# Find the delete marker's VersionId
aws s3api list-object-versions \
  --bucket state-bucket-879381241087 \
  --prefix april26/ecs/terraform.tfstate\
  --query 'DeleteMarkers[*].{VersionId:VersionId,Date:LastModified}'

# Remove the delete marker
aws s3api delete-object \
  --bucket state-bucket-879381241087 \
  --key april26/ecs/terraform.tfstate \
  --version-id dkG22LjVNdob_ZJgaXR2xem7GBVLKuIc