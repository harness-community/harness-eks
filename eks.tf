# create the cluster
#   - tag the cluster security group with the harness required tags for the orchestrator
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "= 21.8.0"

  name               = local.name
  kubernetes_version = var.eks-version

  endpoint_public_access = true

  addons = {
    metrics-server = {
      configuration_values = jsonencode({
        tolerations : [
          {
            effect : "NoSchedule",
            key : "compute",
            operator : "Equal",
            value : "dedicated"
          }
        ]
      })
    }
    coredns = {
      configuration_values = jsonencode({
        tolerations : [
          {
            effect : "NoSchedule",
            key : "compute",
            operator : "Equal",
            value : "dedicated"
          }
        ]
      })
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    vpc-cni = {
      before_compute              = true
      resolve_conflicts_on_create = "OVERWRITE"
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true

  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      name = substr(local.name, 0, 20)

      ami_type = var.ami-type

      instance_types = ["t3.xlarge"]

      min_size     = 1
      max_size     = 3
      desired_size = 1

      taints = {
        compute = {
          key    = "compute"
          value  = "dedicated"
          effect = "NO_SCHEDULE"
        }
      }

      attach_cluster_primary_security_group = true

      tags = var.tags
    }
  }

  # disable control plane logs as its costing ~$60/mo
  enabled_log_types           = []
  create_cloudwatch_log_group = false

  # for ccm cluster orchestrator
  node_security_group_tags = {
    "harness.io/${local.name}" = "owned"
  }
}


locals {
  cluster_tolerations = [{
    key      = "compute"
    operator = "Equal"
    value    = "dedicated"
    effect   = "NoSchedule"
  }]
}