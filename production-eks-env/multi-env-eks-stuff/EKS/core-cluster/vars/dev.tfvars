env = "dev"


eks_nodes = [
  {
    instance_type = "t3.medium"
    desired_size  = 2
    max_size      = 3
    min_size      = 1
  }
]

eks_cluster_endpoint_public_access = true