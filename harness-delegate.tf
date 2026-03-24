# deploy a harness delegate into the cluster
resource "harness_platform_delegatetoken" "eks" {
  name       = "eks-${local.name}-${formatdate("YYYY-MM-DD", timestamp())}"
  account_id = data.harness_platform_current_account.current.id

  lifecycle {
    ignore_changes = [name]
  }
}

resource "kubernetes_namespace_v1" "harness-delegate-ng" {
  metadata {
    name = "harness-delegate-ng"
  }

  depends_on = [module.eks]
}

resource "kubernetes_manifest" "otel-collector" {
  manifest = yamldecode(templatefile("templates/otel-cloudwatch.yaml.tmpl", {
    AWS_REGION    = data.aws_region.current.region
    K8S_NAMESPACE = "harness-delegate-ng"
  }))

  depends_on = [kubernetes_namespace_v1.harness-delegate-ng]
}

module "delegate" {
  source  = "harness/harness-delegate/kubernetes"
  version = "0.2.3"

  account_id       = data.harness_platform_current_account.current.id
  delegate_token   = harness_platform_delegatetoken.eks.value
  delegate_name    = local.name
  deploy_mode      = "KUBERNETES"
  namespace        = "harness-delegate-ng"
  manager_endpoint = var.manager_endpoint
  delegate_image   = "us-docker.pkg.dev/gar-prod-setup/harness-public/harness/delegate:25.10.86901"
  replicas         = 1
  upgrader_enabled = true

  # add additional tags, tolerations, and custom containers (OTEL)
  values = <<EOF
    tags: "orchestrator,aws,eks"
    tolerations:
    - key: "compute"
      operator: "Equal"
      value: "dedicated"
      effect: "NoSchedule"
    custom_envs:
    - name: BLOCK_SHELL_TASK
      value: "true"
    custom_containers:
      - name: otel-collector
        image: otel/opentelemetry-collector-contrib:0.96.0
        imagePullPolicy: IfNotPresent
        command:
          - "/otelcol-contrib"
          - "--config=/etc/otel/otel-collector-config.yaml"
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          runAsUser: 10001
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
        ports:
          - containerPort: 13133
            name: health
            protocol: TCP
          - containerPort: 8888
            name: otel-metrics
            protocol: TCP
        resources:
          limits:
            cpu: "200m"
            memory: "128Mi"
          requests:
            cpu: "50m"
            memory: "64Mi"
        livenessProbe:
          httpGet:
            path: /health
            port: 13133
          initialDelaySeconds: 10
          periodSeconds: 15
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: 13133
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 5
        env:
          - name: ENVIRONMENT
            value: "production"
          - name: DELEGATE_NAME
            value: "${local.name}"
          - name: HARNESS_ACCOUNT_ID
            value: ${data.harness_platform_current_account.current.id}
          - name: K8S_NAMESPACE
            valueFrom:
              fieldRef:
                fieldPath: metadata.namespace
          - name: K8S_POD_NAME
            valueFrom:
              fieldRef:
                fieldPath: metadata.name
          - name: AWS_REGION
            value: ${data.aws_region.current.region}
          - name: AWS_STS_REGIONAL_ENDPOINTS
            value: "regional"
        volumeMounts:
          - name: otel-config
            mountPath: /etc/otel
            readOnly: true

    # Mount OTel config from ConfigMap
    custom_volumes:
      - name: otel-config
        configMap:
          name: otel-collector-config
          items:
            - key: otel-collector-config.yaml
              path: otel-collector-config.yaml
EOF

  depends_on = [kubernetes_manifest.otel-collector]
}

# create the harness k8s connectors
resource "harness_platform_connector_kubernetes" "eks" {
  identifier = "eks_${local.safe_name}"
  name       = "eks-${local.name}"

  inherit_from_delegate {
    delegate_selectors = [local.name]
  }
}

resource "harness_platform_connector_kubernetes_cloud_cost" "eks" {
  identifier = "eks_${local.safe_name}_ccm"
  name       = "eks-${local.name}-ccm"

  features_enabled = ["VISIBILITY", "OPTIMIZATION"]
  connector_ref    = harness_platform_connector_kubernetes.eks.id
}

# delegate iam role
resource "aws_iam_role" "delegate" {
  name = "harness-delegate-${local.name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/eks-cluster-arn"            = module.eks.cluster_arn
            "aws:RequestTag/kubernetes-namespace"       = "harness-delegate-ng"
            "aws:RequestTag/kubernetes-service-account" = local.name
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "delegate" {
  name = "${local.name}-s3-read-policy"
  role = aws_iam_role.delegate.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "Harness/Delegates"
          }
        }
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/metrics/harness/*",
          "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/metrics/harness/*:*"
        ]
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "delegate" {
  cluster_name    = module.eks.cluster_name
  namespace       = "harness-delegate-ng"
  service_account = local.name
  role_arn        = aws_iam_role.delegate.arn
}