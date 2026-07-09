# ─────────────────────────────────────────
# NAMESPACES — explicit, independent resources
# ─────────────────────────────────────────

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = "external-secrets"
  }
}

resource "kubernetes_namespace" "argo_rollouts" {
  metadata {
    name = "argo-rollouts"
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# ─────────────────────────────────────────
# AWS Load Balancer Controller
# ─────────────────────────────────────────
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.alb_controller_version

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 300

  set {
    name  = "clusterName"
    value = var.cluster_name
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.alb_controller_role_arn
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = var.vpc_id
  }
  set {
    name  = "replicaCount"
    value = var.alb_controller_replica_count
  }
}

# ─────────────────────────────────────────
# EBS CSI Driver
# ─────────────────────────────────────────
resource "helm_release" "ebs_csi_driver" {
  name       = "aws-ebs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart      = "aws-ebs-csi-driver"
  namespace  = "kube-system"
  version    = var.ebs_csi_version

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 300

  set {
    name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.ebs_csi_role_arn
  }
}


# ─────────────────────────────────────────
# Kong API Gateway
# Ingress Controller for EKS-internal
# microservice routing. DB-less mode —
# config driven by K8s CRDs, no Postgres.
# ─────────────────────────────────────────
resource "kubernetes_namespace" "kong" {
  metadata {
    name = "kong"
  }
}

resource "helm_release" "kong" {
  name       = "kong"
  repository = "https://charts.konghq.com"
  chart      = "kong"
  namespace  = kubernetes_namespace.kong.metadata[0].name
  version    = var.kong_version

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 300

  values = [<<-YAML
    env:
      database: "off"

    ingressController:
      enabled: true
      installCRDs: false

    admin:
      enabled: false

    proxy:
      type: LoadBalancer
      annotations:
        service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
        service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
        service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"

    replicaCount: ${var.kong_replica_count}

    resources:
      requests:
        cpu: 250m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
  YAML
  ]

  depends_on = [
    helm_release.aws_load_balancer_controller,
    kubernetes_namespace.kong,
  ]
}


# ─────────────────────────────────────────
# Default StorageClass — gp3 via EBS CSI
# ─────────────────────────────────────────
resource "kubernetes_storage_class" "gp3_default" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type      = "gp3"
    fsType    = "ext4"
    encrypted = "true"
  }

  depends_on = [helm_release.ebs_csi_driver]
}

# ─────────────────────────────────────────
# Metrics Server
# ─────────────────────────────────────────
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = var.metrics_server_version

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 180
}

# ─────────────────────────────────────────
# Cluster Autoscaler
# ─────────────────────────────────────────
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = var.cluster_autoscaler_version

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 300

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }
  set {
    name  = "awsRegion"
    value = var.region
  }
  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.cluster_autoscaler_role_arn
  }

  depends_on = [helm_release.metrics_server]
}

# ─────────────────────────────────────────
# ArgoCD
# ─────────────────────────────────────────
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = var.argocd_version

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 600

  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }
  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }
  set {
    name  = "server.replicas"
    value = var.argocd_server_replicas
  }
  set {
    name  = "repoServer.replicas"
    value = var.argocd_repo_server_replicas
  }

  depends_on = [
    helm_release.aws_load_balancer_controller,
    kubernetes_namespace.argocd,
  ]
}

# ─────────────────────────────────────────
# ArgoCD Ingress
# ─────────────────────────────────────────
resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-ingress"
    namespace = kubernetes_namespace.argocd.metadata[0].name

    annotations = {
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "argocd-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.argocd]
}

# ─────────────────────────────────────────
# External Secrets
# ─────────────────────────────────────────
resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = kubernetes_namespace.external_secrets.metadata[0].name
  version    = "0.9.11"

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 300

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.external_secrets_role_arn
  }

  depends_on = [
    helm_release.argocd,
    kubernetes_namespace.external_secrets,
  ]
}

# ─────────────────────────────────────────
# Argo Rollouts
# ─────────────────────────────────────────
resource "helm_release" "argo_rollouts" {
  name       = "argo-rollouts"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-rollouts"
  namespace  = kubernetes_namespace.argo_rollouts.metadata[0].name
  version    = "2.37.7"

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 300

  depends_on = [
    helm_release.argocd,
    kubernetes_namespace.argo_rollouts,
  ]
}

# ─────────────────────────────────────────
# Prometheus
# ─────────────────────────────────────────
resource "helm_release" "prometheus_stack" {
  name       = "prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "58.7.2"

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 600

  # Allow Prometheus to scrape ServiceMonitors from all namespaces
  # (not just the monitoring namespace) — required for app-dev services.
  values = [<<-YAML
    prometheus:
      prometheusSpec:
        serviceMonitorSelectorNilUsesHelmValues: false
        serviceMonitorSelector: {}
        serviceMonitorNamespaceSelector: {}
    grafana:
      additionalDataSources:
        - name: Loki
          type: loki
          url: http://loki-gateway.monitoring.svc.cluster.local:80
          access: proxy
          isDefault: false
        - name: Tempo
          type: tempo
          url: http://tempo.monitoring.svc.cluster.local:3100
          access: proxy
          isDefault: false
  YAML
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
    kubernetes_storage_class.gp3_default,
  ]
}

# ─────────────────────────────────────────
# Loki — log aggregation
# Configured in single-binary (monolithic)
# mode for simplicity on a dev cluster.
# Uses gp3 for persistent log storage.
# ─────────────────────────────────────────
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "6.6.2"

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 600

  values = [<<-YAML
    deploymentMode: SingleBinary
    loki:
      auth_enabled: false
      commonConfig:
        replication_factor: 1
      storage:
        type: filesystem
      schemaConfig:
        configs:
          - from: "2024-01-01"
            store: tsdb
            object_store: filesystem
            schema: v13
            index:
              prefix: loki_index_
              period: 24h
    singleBinary:
      replicas: 1
      persistence:
        enabled: true
        storageClass: gp3
        size: 10Gi
    gateway:
      enabled: true
    # Disable components not needed in single-binary mode
    read:
      replicas: 0
    write:
      replicas: 0
    backend:
      replicas: 0
  YAML
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
    kubernetes_storage_class.gp3_default,
    helm_release.prometheus_stack,
  ]
}

# ─────────────────────────────────────────
# Promtail — ships pod logs to Loki
# Runs as a DaemonSet on every node,
# tails /var/log/pods/* and forwards to Loki.
# ─────────────────────────────────────────
resource "helm_release" "promtail" {
  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "6.16.4"

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 300

  values = [<<-YAML
    config:
      clients:
        - url: http://loki-gateway.monitoring.svc.cluster.local:80/loki/api/v1/push
    # Add service/namespace labels to every log line for easy filtering
    extraScrapeConfigs: |
      - job_name: kubernetes-pods
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_namespace]
            target_label: namespace
          - source_labels: [__meta_kubernetes_pod_label_app]
            target_label: app
          - source_labels: [__meta_kubernetes_pod_name]
            target_label: pod
  YAML
  ]

  depends_on = [helm_release.loki]
}

# ─────────────────────────────────────────
# Tempo — distributed tracing backend
# Single-binary mode, filesystem storage.
# Services send traces via OTLP gRPC (4317)
# or HTTP (4318).
# ─────────────────────────────────────────
resource "helm_release" "tempo" {
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "1.10.1"

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 300

  values = [<<-YAML
    tempo:
      storage:
        trace:
          backend: local
          local:
            path: /var/tempo/traces
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317
            http:
              endpoint: 0.0.0.0:4318
    persistence:
      enabled: true
      storageClassName: gp3
      size: 10Gi
    serviceMonitor:
      enabled: true
  YAML
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
    kubernetes_storage_class.gp3_default,
    helm_release.prometheus_stack,
  ]
}

# ─────────────────────────────────────────
# Random passwords for MongoDB
# ─────────────────────────────────────────
resource "random_password" "mongodb_root" {
  length  = 20
  special = false
}

resource "random_password" "mongodb_user" {
  length  = 20
  special = false
}

# ─────────────────────────────────────────
# MongoDB
# ─────────────────────────────────────────
resource "helm_release" "mongodb" {
  name       = "mongodb"
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "mongodb"
  namespace  = "app-dev"
  version    = "19.1.15"

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 900

  set {
    name  = "auth.enabled"
    value = "true"
  }
  set {
    name  = "auth.rootUser"
    value = "root"
  }
  set {
    name  = "auth.rootPassword"
    value = random_password.mongodb_root.result
  }
  set {
    name  = "auth.databases[0]"
    value = "notification_db"
  }
  set {
    name  = "auth.usernames[0]"
    value = "notificationuser"
  }
  set {
    name  = "auth.passwords[0]"
    value = random_password.mongodb_user.result
  }
  set {
    name  = "architecture"
    value = "standalone"
  }
  set {
    name  = "persistence.enabled"
    value = "true"
  }
  set {
    name  = "persistence.storageClass"
    value = "gp3"
  }
  set {
    name  = "persistence.size"
    value = "8Gi"
  }

  depends_on = [
    helm_release.argocd,
    kubernetes_storage_class.gp3_default,
  ]
}

# ─────────────────────────────────────────
# MongoDB Secret in AWS Secrets Manager
# ─────────────────────────────────────────
resource "aws_secretsmanager_secret" "mongodb" {
  name                    = "${var.env}/microservices/mongodb"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "mongodb" {
  secret_id = aws_secretsmanager_secret.mongodb.id
  secret_string = jsonencode({
    MONGO_URI = "mongodb://notificationuser:${random_password.mongodb_user.result}@mongodb.app-dev.svc.cluster.local:27017/notification_db"
    DB_NAME   = "notification_db"
  })

  depends_on = [helm_release.mongodb]
}