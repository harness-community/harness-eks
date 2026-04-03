data "harness_platform_current_account" "current" {}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "random_pet" "name" {}

locals {
  name      = var.name != null ? var.name : random_pet.name.id
  safe_name = replace(local.name, "-", "_")
}

output "name" {
  description = "Name"
  value       = local.name
}