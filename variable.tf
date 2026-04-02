variable "name" {
  type        = string
  default     = null
  description = "Name prefix for the cluster"
}

variable "eks-version" {
  type        = string
  default     = "1.33"
  description = "EKS version to use"
}

variable "ami-type" {
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
  description = "AMI type to use"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the cluster nodes"
}

variable "manager_endpoint" {
  type        = string
  default     = "https://app.harness.io/gratis"
  description = "Manager endpoint for the delegate"
}

variable "orchestrator_tag" {
  type        = string
  default     = "0.8.2"
  description = "Tag for the orchestrator"
}

variable "build_vm_ami_id" {
  type        = string
  default     = "ami-0f4f85bd3b0ba1cb9"
  description = "AMI ID for the build farm VMs"
}

variable "delegate_image" {
  type        = string
  default     = "us-docker.pkg.dev/gar-prod-setup/harness-public/harness/delegate:26.03.88802"
  description = "Image for the delegate"
}

variable "delegate_namespace" {
  type        = string
  default     = "harness-delegate-ng"
  description = "Namespace for the delegate"
}

variable "byoc_namespace" {
  type        = string
  default     = "byoc"
  description = "Namespace for the byoc control plane"
}
