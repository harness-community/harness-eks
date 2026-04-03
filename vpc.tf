# create the vpc
#   - tag the vpc subnets with the harness required tags for the orchestrator
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = local.name
  cidr = "10.0.0.0/16"

  azs             = ["${data.aws_region.current.region}a", "${data.aws_region.current.region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.2.0/24", "10.0.4.0/24"]

  enable_dns_hostnames = true

  public_subnet_tags = {
    "type" = "public"
    "vpc"  = local.name
  }

  private_subnet_tags = {
    "type" = "private"
    "vpc"  = local.name

    # for ccm cluster orchestrator
    "harness.io/${local.name}" = "owned"
  }

  default_security_group_egress = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  default_security_group_ingress = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "10.0.0.0/16"
    }
  ]
}

locals {
  index_list                 = [for i in range(length(module.vpc.private_route_table_ids)) : tostring(i)]
  zipped_private_routetables = zipmap(local.index_list, module.vpc.private_route_table_ids)
}

# use fck nat instead of aws nat gateway to save 90% of costs
# https://fck-nat.dev/stable/
module "fck-nat" {
  source = "RaJiska/fck-nat/aws"

  name      = "${local.name}-fck-nat"
  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.public_subnets[0]

  update_route_tables = true
  route_tables_ids    = local.zipped_private_routetables
}
