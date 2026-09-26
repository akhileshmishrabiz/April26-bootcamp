
# # Allow kubelets on Karpenter-launched EC2 instances to join the cluster.
# # EKS 1.33 uses Access Entries (not aws-auth) — type EC2_LINUX maps the node role.
resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = local.eks_cluster_name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"
}

# # Tag the private subnets so the EC2NodeClass `subnetSelectorTerms` finds them.
resource "aws_ec2_tag" "subnet_discovery" {
  for_each    = toset(data.aws_subnets.private.ids)
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = local.eks_cluster_name
}

# # Tag the EKS-managed cluster primary security group so the EC2NodeClass
# # `securityGroupSelectorTerms` finds it.
resource "aws_ec2_tag" "cluster_sg_discovery" {
  resource_id = data.aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = local.eks_cluster_name
}

# # Tag the managed node group security group too. Without this, Karpenter nodes
# # only get the cluster SG and cannot reach pods on managed nodes (and vice versa).
resource "aws_ec2_tag" "node_sg_discovery" {
  resource_id = data.aws_security_group.node.id
  key         = "karpenter.sh/discovery"
  value       = local.eks_cluster_name
}


# # sqs queue for karpenter

resource "aws_sqs_queue" "karpenter" {
  name                      = "karpenter-${local.eks_cluster_name}"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue_policy" "karpenter" {
  queue_url = aws_sqs_queue.karpenter.url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["events.amazonaws.com", "sqs.amazonaws.com"]
      }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.karpenter.arn
    }]
  })
}

# # ---- EventBridge rules → SQS interruption queue ----------------------------

resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "karpenter-${local.eks_cluster_name}-spot-interruption"
  description = "EC2 Spot Instance Interruption Warning"
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Spot Instance Interruption Warning"]
  })
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule      = aws_cloudwatch_event_rule.spot_interruption.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "rebalance" {
  name        = "karpenter-${local.eks_cluster_name}-rebalance"
  description = "EC2 Instance Rebalance Recommendation"
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance Rebalance Recommendation"]
  })
}

resource "aws_cloudwatch_event_target" "rebalance" {
  rule      = aws_cloudwatch_event_rule.rebalance.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "scheduled_change" {
  name        = "karpenter-${local.eks_cluster_name}-scheduled-change"
  description = "AWS Health Scheduled Change"
  event_pattern = jsonencode({
    source        = ["aws.health"]
    "detail-type" = ["AWS Health Event"]
  })
}

resource "aws_cloudwatch_event_target" "scheduled_change" {
  rule      = aws_cloudwatch_event_rule.scheduled_change.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "instance_state_change" {
  name        = "karpenter-${local.eks_cluster_name}-instance-state-change"
  description = "EC2 Instance State-change Notification"
  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
  })
}

resource "aws_cloudwatch_event_target" "instance_state_change" {
  rule      = aws_cloudwatch_event_rule.instance_state_change.name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter.arn
}

# # 
# # Karpenter custom resources. The kubectl provider (gavinbunney/kubectl) is used
# # instead of kubernetes_manifest because it does not require the CRDs to exist
# # at plan time — they are installed by the helm_release above.

resource "kubectl_manifest" "ec2nodeclass_default" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      amiFamily = "AL2023"
      amiSelectorTerms = [
        { alias = "al2023@latest" },
      ]
      role = aws_iam_role.karpenter_node.name
      subnetSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = local.eks_cluster_name
          }
        },
      ]
      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = local.eks_cluster_name
          }
        },
      ]
      tags = {
        "karpenter.sh/discovery" = local.eks_cluster_name
      }
    }
  })

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "nodepool_default" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "default"
    }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              # values   = ["spot", "on-demand"]
              values   = ["on-demand"]
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "kubernetes.io/os"
              operator = "In"
              values   = ["linux"]
            },
            # Previous: c/m/r compute-optimized / general / memory instances (e.g. c6a.large)
            # {
            #   key      = "karpenter.k8s.aws/instance-category"
            #   operator = "In"
            #   values   = ["c", "m", "r"]
            # },
            # {
            #   key      = "karpenter.k8s.aws/instance-generation"
            #   operator = "Gt"
            #   values   = ["2"]
            # },
            # Match the EKS managed node group — burstable t3 (same as eks-infra/eks.tf)
            {
              key      = "karpenter.k8s.aws/instance-family"
              operator = "In"
              values   = ["t3", "t4g"]
            },
            # t3.small caps at 11 pods and ~2 GiB allocatable memory — too tight for
            # Prometheus (1 Gi request), Grafana, and ecommerce workloads. Require medium+.
            {
              key      = "karpenter.k8s.aws/instance-size"
              operator = "NotIn"
              values   = [ "small", "medium", "large"]
            },
          ]
          expireAfter = "720h"
        }
      }
      limits = {
        cpu = 5
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
      }
    }
  })

  depends_on = [kubectl_manifest.ec2nodeclass_default]
}


# # helm karpenter
resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = var.karpenter_namespace
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_version
  create_namespace = false

  set = [
    {
      name  = "settings.clusterName"
      value = local.eks_cluster_name
    },
    {
      name  = "settings.interruptionQueue"
      value = aws_sqs_queue.karpenter.name
    },
    {
      name  = "serviceAccount.name"
      value = var.karpenter_sa
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.karpenter_controller.arn
    },
    {
      name  = "controller.resources.requests.cpu"
      value = "200m"
    },
    {
      name  = "controller.resources.requests.memory"
      value = "256Mi"
    },
    {
      name  = "replicas"
      value = "1"
    },
  ]

  depends_on = [
    aws_iam_role_policy_attachment.karpenter_controller,
    aws_eks_access_entry.karpenter_node,
    aws_sqs_queue_policy.karpenter,
  ]
}
