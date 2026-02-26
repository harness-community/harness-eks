# harness eks

this module will deploy an end-to-end aws vpc and eks cluster with every possible harness component installed

TODO
- byoc
- turn fck-nat into an autostopping proxy
- autostopping v2
- chaos?

## whats in the box

deploy a new vpc and eks cluster using aws modules bootrstrapped with a harness delegate and connectors

then create the cluster orchestrator components in aws, the orchestrator resource in harness, and configure the orchestrator

this will need to be done in two parts, saving the helm install for the delegate and orchestrator until after the cluster is created

this can be done with opentofu's -exclude option:
```
tofu apply -exclude="module.delegate.helm_release.delegate"
```

then a full apply can be done:
```
tofu apply
```

## vpc

`vpc.tf`

provision a vpc with public and private subnets

use [fck-nat](https://fck-nat.dev/) instead of aws nat gateway to save 90% of costs

tag subnets and security groups with the nessesary values for the orchestrator to find them:
```
"harness.io/${cluster name}" = "owned"
```

## eks

`eks.tf`

provision an EKS cluster with a single dedicated node to run the orchestrator and delegate

create a harness delegate token, deploy a delegate using helm, and create a k8s and ccm k8s connector at the account level

a basic cluster, to run a few add-ons, the delegate, and the orchestrator components has the following resource needs:
```
│   cpu      1350m (34%)   2 (51%)       │
│   memory   2188Mi (14%)  4536Mi (30%)  │
```

we can use a single t4g.medium ($30/mo on-demand) node to run dedicated components, this combined with the $70 base cost of EKS gives our cluster a total cost of $100/mo before workloads are provisioned

if we were to use fargate pods for the delegate and orchestrator the cost would be x2 a single t3.medium ($0.068/hr)

| Comp     | CPU        | MEM         | Size   | Fargate Cost |
|----------|------------|-------------|--------|--------------|
| Delegate | 0.04048/hr | 0.004445/hr | 1x4    | 0.05826/hr   |
| Orch     | 0.04048/hr | 0.004445/hr | .25x.5 | 0.0123425/hr |
|          |            |             |        |              |
| Total    |            |             |        | 0.0706025/hr |

adding a taint to the default dedicated nodepool and corresponding toleration to the orchestrator and delegate (along with addones) will allow the system componenets to run on this node while workloads run on compute provisioned by the orchestrator

```
tolerations:
- key: "compute"
  operator: "Equal"
  value: "dedicated"
  effect: "NoSchedule"
```

## delegate

`harness-delegate.tf`

deploy a harness delegate into the cluster using helm

configure an OTEL sidecar to send delegate metrics to cloudwatch

the delegate can run on the dedicated nodes in the cluster

## cluster orchestrator

`harness-cluster-orchestrator.tf`

deploy the orchestrator into the cluster using helm

configure the cluster for 100% spot usage

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.2.0 |
| aws | >= 4.16 |
| harness | >= 0.34.0 |

## Providers

| Name | Version |
|------|---------|
| aws | 6.17.0 |
| harness | 0.38.9 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_ec2_tag.cluster_ami_tag](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_tag) | resource |
| [aws_ec2_tag.cluster_security_group_tag](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_tag) | resource |
| [aws_ec2_tag.cluster_subnet_tag](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_tag) | resource |
| [aws_eks_access_entry.node_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_iam_instance_profile.instance_profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_policy.controller_role_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.controller_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.node_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.controller_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [harness_cluster_orchestrator.cluster_orchestrator](https://registry.terraform.io/providers/harness/harness/latest/docs/resources/cluster_orchestrator) | resource |
| [harness_platform_apikey.api_key](https://registry.terraform.io/providers/harness/harness/latest/docs/resources/platform_apikey) | resource |
| [harness_platform_role_assignments.cluster_orch_role](https://registry.terraform.io/providers/harness/harness/latest/docs/resources/platform_role_assignments) | resource |
| [harness_platform_service_account.cluster_orch_service_account](https://registry.terraform.io/providers/harness/harness/latest/docs/resources/platform_service_account) | resource |
| [harness_platform_token.api_token](https://registry.terraform.io/providers/harness/harness/latest/docs/resources/platform_token) | resource |
| [aws_iam_policy_document.assume_inline_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.controller_trust_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_ssm_parameter.ami](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |
| [harness_platform_current_account.current](https://registry.terraform.io/providers/harness/harness/latest/docs/data-sources/platform_current_account) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| ami\_type | Type of AMI to use for the node group | `string` | `"AL2_x86_64"` | no |
| ccm\_k8s\_connector\_id | harness ccm kubernetes connector for the cluster | `string` | n/a | yes |
| cluster\_amis | AMIs used in your EKS cluster; If passed will be tagged with required orchestrator labels | `list(string)` | `[]` | no |
| cluster\_endpoint | EKS cluster endpoint | `string` | n/a | yes |
| cluster\_name | EKS cluster Name | `string` | n/a | yes |
| cluster\_oidc\_arn | OIDC Provder ARN for the cluster | `string` | n/a | yes |
| cluster\_security\_group\_ids | Security group IDs used in your EKS cluster; If passed will be tagged with required orchestrator labels | `list(string)` | `[]` | no |
| cluster\_subnet\_ids | Subnet IDs used in your EKS cluster; If passed will be tagged with required orchestrator labels | `list(string)` | `[]` | no |
| kubernetes\_version | Kubernetes version to use for the node group. Required if ami\_type is set | `string` | `null` | no |
| node\_role\_policies | List of IAM policies to attach to the node role | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| eks\_cluster\_amis | n/a |
| eks\_cluster\_controller\_role\_arn | n/a |
| eks\_cluster\_default\_instance\_profile | n/a |
| eks\_cluster\_node\_role\_arn | n/a |
| harness\_ccm\_token | n/a |
| harness\_cluster\_orchestrator\_id | n/a |