# create the orchestrator components in aws and harness
module "cluster-orchestrator" {
  source = "git::https://github.com/harness-community/terraform-aws-harness-ccm-cluster-orchestrator.git"

  cluster_name     = module.eks.cluster_name
  cluster_endpoint = module.eks.cluster_endpoint
  # cluster_oidc_arn = module.eks.oidc_provider_arn
  use_eks_pod_identity = true

  ami_type           = var.ami-type
  kubernetes_version = var.eks-version

  ccm_k8s_connector_id = harness_platform_connector_kubernetes_cloud_cost.eks.id
}

# define your specific settings for how the orchestrator should run
# currently broken - fix ccm-
resource "harness_cluster_orchestrator_config" "orchestrator" {
  orchestrator_id = module.cluster-orchestrator.harness_cluster_orchestrator_id
  distribution {
    ondemand_replica_percentage = 0.0
    selector                    = "ALL"
    strategy                    = "CostOptimized"
  }
  binpacking {
    disruption {
      delay = "Never"
    }
  }

  node_preferences {}
}

# deploy the orchestrator into the cluster
resource "helm_release" "orchestrator" {
  name             = "harness-ccm-cluster-orchestrator"
  repository       = "https://lightwing-downloads.s3.ap-southeast-1.amazonaws.com/cluster-orchestrator-helm-chart"
  chart            = "harness-ccm-cluster-orchestrator"
  namespace        = "kube-system"
  create_namespace = false

  values = [yamlencode({
    harness = {
      accountID      = data.harness_platform_current_account.current.id
      k8sConnectorID = harness_platform_connector_kubernetes_cloud_cost.eks.id
    }
    eksCluster = {
      name              = module.eks.cluster_name
      region            = data.aws_region.current.region
      controllerRoleARN = module.cluster-orchestrator.eks_cluster_controller_role_arn
      endpoint          = module.eks.cluster_endpoint
      defaultInstanceProfile = {
        name = module.cluster-orchestrator.eks_cluster_default_instance_profile
      }
      nodeRole = {
        arn = module.cluster-orchestrator.eks_cluster_node_role_arn
      }
    }
    clusterOrchestrator = {
      id = module.cluster-orchestrator.harness_cluster_orchestrator_id
      image = {
        tag = var.orchestrator_tag
      }
      tolerations = local.cluster_tolerations
      distributor = {
        enabled     = false
        tolerations = local.cluster_tolerations
      }
    }
  })]

  set_sensitive {
    name  = "harness.ccm.secret.token"
    value = module.cluster-orchestrator.harness_ccm_token
    type  = "string"
  }

  depends_on = [module.delegate]
}