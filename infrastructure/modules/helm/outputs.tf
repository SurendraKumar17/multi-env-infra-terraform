output "argocd_hostname" {
  description = "ALB hostname for ArgoCD"
  value       = try(kubernetes_ingress_v1.argocd.status[0].load_balancer[0].ingress[0].hostname, "")
}


output "kong_proxy_service" {
  description = "Kong proxy internal DNS name for retrieving LoadBalancer address after apply"
  value       = "kong-kong-proxy.kong.svc.cluster.local"
}