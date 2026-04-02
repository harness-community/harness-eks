locals {
  log_group_path = "/harness/delegates"
}

# deploy a harness delegate into the cluster
resource "random_id" "resource_trigger" {
  byte_length = 2
}

resource "harness_platform_delegatetoken" "eks" {
  name       = "eks-${local.name}-${formatdate("YYYY-MM-DD", timestamp())}-${random_id.resource_trigger.hex}"
  account_id = data.harness_platform_current_account.current.id

  lifecycle {
    ignore_changes = [name]
  }
}

resource "kubernetes_namespace_v1" "harness-delegate-ng" {
  metadata {
    name = var.delegate_namespace
  }

  depends_on = [module.eks]
}

resource "kubernetes_manifest" "otel-collector" {
  manifest = yamldecode(templatefile("templates/otel-cloudwatch.yaml.tmpl", {
    AWS_REGION     = data.aws_region.current.region
    K8S_NAMESPACE  = var.delegate_namespace
    LOG_GROUP_PATH = local.log_group_path
    RETENTION_DAYS = 1
  }))

  depends_on = [kubernetes_namespace_v1.harness-delegate-ng]
}

resource "kubernetes_manifest" "delegate-logger" {
  manifest = yamldecode(templatefile("templates/delegate-logger.yaml.tmpl", {
    K8S_NAMESPACE = var.delegate_namespace
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
  namespace        = var.delegate_namespace
  manager_endpoint = var.manager_endpoint
  delegate_image   = var.delegate_image
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
    - name: HARNESS_LOG_STREAMING_STDOUT_ENABLED
      value: "true"
    - name: JAVA_OPTS
      value: "-Dlogback.configurationFile=/opt/harness-delegate/logback/delegate-logger.xml"
    - name: RUNNER_URL
      value: "http://byoc-byoc-controlplane.${var.byoc_namespace}.svc.cluster.local:3000"
    custom_mounts:
    - name: delegate-logging
      mountPath: /opt/harness-delegate/logback/
    - name: shared-logs
      mountPath: /opt/harness-delegate/logs
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
          - name: shared-logs
            mountPath: /opt/harness-delegate/logs
            readOnly: true

    # Mount OTel config from ConfigMap
    custom_volumes:
      - name: shared-logs
        emptyDir: {}
      - name: otel-config
        configMap:
          name: ${kubernetes_manifest.otel-collector.object.metadata.name}
          items:
            - key: otel-collector-config.yaml
              path: otel-collector-config.yaml
      - name: delegate-logging
        configMap:
          name: ${kubernetes_manifest.delegate-logger.object.metadata.name}
          items:
            - key: delegate-logger.xml
              path: delegate-logger.xml
EOF

  depends_on = [kubernetes_manifest.otel-collector, kubernetes_manifest.delegate-logger]
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
  name = "${local.name}-logging"
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
          "logs:PutRetentionPolicy",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_path}*",
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