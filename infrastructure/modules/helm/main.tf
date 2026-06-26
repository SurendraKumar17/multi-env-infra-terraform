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

  depends_on = [kubernetes_namespace.monitoring]
}

# ─────────────────────────────────────────
# MongoDB
# ─────────────────────────────────────────
resource "helm_release" "mongodb" {
  name       = "mongodb"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "mongodb"
  namespace  = "app-dev"
  version    = "15.6.18"

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 300

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
    value = "changeme"
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
    value = "changeme"
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
    name  = "persistence.size"
    value = "8Gi"
  }

  depends_on = [helm_release.argocd]
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
    MONGO_URI = "mongodb://notificationuser:changeme@mongodb.app-dev.svc.cluster.local:27017/notification_db"
    DB_NAME   = "notification_db"
  })

  depends_on = [helm_release.mongodb]
}