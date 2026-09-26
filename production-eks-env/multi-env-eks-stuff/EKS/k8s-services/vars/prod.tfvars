env = "prod"


eks_nodes = [
  {
    instance_type = "t3.large"
    desired_size  = 3
    max_size      = 5
    min_size      = 2
  }
]

eks_cluster_endpoint_public_access = false