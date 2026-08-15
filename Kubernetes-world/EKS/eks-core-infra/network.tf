module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version ="6.6.1"

  name = var.vpc_name
  cidr = var.vpc_cidr

    azs             = ["${var.region}a", "${var.region}b"]
    private_subnets = var.private_subnets_cidr
    public_subnets  = var.public_subnets_cidr

   enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

   public_subnet_tags = {
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    "kubernetes.io/role/elb"                        = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    # "kubernetes.io/role/internal-elb"               = "1"
  }
}
