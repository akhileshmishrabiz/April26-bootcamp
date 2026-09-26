# ============================================================================
# Karpenter Controller IAM Role  (IRSA — assumed by the karpenter ServiceAccount)
# ============================================================================

resource "aws_iam_role" "karpenter_controller" {
  name = "karpenter-controller-${local.eks_cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:${var.karpenter_namespace}:${var.karpenter_sa}"
          "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "karpenter_controller" {
  name = "karpenter-controller-${local.eks_cluster_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowScopedEC2InstanceAccessActions"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}::image/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}::snapshot/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:security-group/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:subnet/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:capacity-reservation/*",
        ]
        Action = ["ec2:RunInstances", "ec2:CreateFleet"]
      },
      {
        Sid      = "AllowScopedEC2LaunchTemplateAccessActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:launch-template/*"
        Action   = ["ec2:RunInstances", "ec2:CreateFleet"]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${local.eks_cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedEC2InstanceActionsWithTags"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:fleet/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:volume/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:network-interface/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:launch-template/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:spot-instances-request/*",
        ]
        Action = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${local.eks_cluster_name}" = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                      = local.eks_cluster_name
          }
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedResourceCreationTagging"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:fleet/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:volume/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:network-interface/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:launch-template/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:spot-instances-request/*",
        ]
        Action = "ec2:CreateTags"
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${local.eks_cluster_name}" = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                      = local.eks_cluster_name
            "ec2:CreateAction"                                         = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
          }
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid      = "AllowScopedResourceTagging"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:instance/*"
        Action   = "ec2:CreateTags"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${local.eks_cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
          StringEqualsIfExists = {
            "aws:RequestTag/eks:eks-cluster-name" = local.eks_cluster_name
          }
          "ForAllValues:StringEquals" = {
            "aws:TagKeys" = [
              "eks:eks-cluster-name",
              "karpenter.sh/nodeclaim",
              "Name",
            ]
          }
        }
      },
      {
        Sid    = "AllowScopedDeletion"
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:instance/*",
          "arn:${data.aws_partition.current.partition}:ec2:${var.region}:*:launch-template/*",
        ]
        Action = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${local.eks_cluster_name}" = "owned"
          }
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid      = "AllowRegionalReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      {
        Sid      = "AllowSSMReadActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:ssm:${var.region}::parameter/aws/service/*"
        Action   = "ssm:GetParameter"
      },
      {
        Sid      = "AllowPricingReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action   = "pricing:GetProducts"
      },
      {
        Sid      = "AllowInterruptionQueueActions"
        Effect   = "Allow"
        Resource = aws_sqs_queue.karpenter.arn
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage",
        ]
      },
      {
        Sid      = "AllowPassingInstanceRole"
        Effect   = "Allow"
        Resource = aws_iam_role.karpenter_node.arn
        Action   = "iam:PassRole"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = ["ec2.amazonaws.com", "ec2.amazonaws.com.cn"]
          }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileCreationActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
        Action   = ["iam:CreateInstanceProfile"]
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${local.eks_cluster_name}" = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                      = local.eks_cluster_name
            "aws:RequestTag/topology.kubernetes.io/region"             = var.region
          }
          StringLike = {
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileTagActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
        Action   = ["iam:TagInstanceProfile"]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${local.eks_cluster_name}" = "owned"
            "aws:ResourceTag/topology.kubernetes.io/region"             = var.region
            "aws:RequestTag/kubernetes.io/cluster/${local.eks_cluster_name}"  = "owned"
            "aws:RequestTag/eks:eks-cluster-name"                       = local.eks_cluster_name
            "aws:RequestTag/topology.kubernetes.io/region"              = var.region
          }
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"  = "*"
          }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile",
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${local.eks_cluster_name}" = "owned"
            "aws:ResourceTag/topology.kubernetes.io/region"             = var.region
          }
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },
      {
        Sid      = "AllowInstanceProfileReadActions"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
        Action   = "iam:GetInstanceProfile"
      },
      {
        Sid      = "AllowAPIServerEndpointDiscovery"
        Effect   = "Allow"
        Resource = "arn:${data.aws_partition.current.partition}:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${local.eks_cluster_name}"
        Action   = "eks:DescribeCluster"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

# ============================================================================
# Karpenter Node IAM Role  (assumed by EC2 instances Karpenter launches)
# ============================================================================

resource "aws_iam_role" "karpenter_node" {
  name = "karpenter-node-${local.eks_cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
