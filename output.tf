output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "Public Subnets"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "Private Subnets"
  value       = module.vpc.private_subnets
}

output "cluster_id" {
  description = "Cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "Cluster Endpoint"
  value       = module.eks.cluster_endpoint
}

output "ccm_k8s_connector_id" {
  description = "CCM Kubernetes Connector ID"
  value       = harness_platform_connector_kubernetes_cloud_cost.eks.id
}

output "harness_ccm_token" {
  value     = module.cluster-orchestrator.harness_ccm_token
  sensitive = true
}

output "eks_cluster_controller_role_arn" {
  value = module.cluster-orchestrator.eks_cluster_controller_role_arn
}

output "eks_cluster_default_instance_profile" {
  value = module.cluster-orchestrator.eks_cluster_default_instance_profile
}

output "eks_cluster_node_role_arn" {
  value = module.cluster-orchestrator.eks_cluster_node_role_arn
}

output "harness_cluster_orchestrator_id" {
  value = module.cluster-orchestrator.harness_cluster_orchestrator_id
}

output "eks_cluster_amis" {
  value = module.cluster-orchestrator.eks_cluster_amis
}