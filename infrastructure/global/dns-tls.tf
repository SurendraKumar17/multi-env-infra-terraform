# =============================================================
# infrastructure/global/dns-tls.tf
#
# Route53 hosted zone + ACM wildcard certificate, shared across all
# environments. Each env's ArgoCD/ingress gets a subdomain off this
# one zone (dev.yourdomain.com, staging.yourdomain.com,
# yourdomain.com for prod) instead of each env owning its own zone.
#
# ⚠️ YOU DO NOT HAVE A REAL DOMAIN YET. This file will NOT apply
# successfully as-is:
#   - aws_route53_zone creates a hosted zone, but a hosted zone alone
#     doesn't make DNS resolve — you must OWN the domain and point
#     its registrar's nameservers at the ones this zone outputs.
#   - aws_acm_certificate + the validation resource below will hang
#     indefinitely waiting for DNS validation that can never complete
#     until the above step is done.
#
# RECOMMENDED: leave var.root_domain = "" (default) until you've
# registered a real domain (Route53 itself, or any registrar). Then:
#   1. Set var.root_domain to your real domain
#   2. terraform apply — creates the hosted zone
#   3. Copy the NS records from the zone's output to your registrar
#   4. Wait for propagation (minutes to ~48h depending on registrar)
#   5. Re-run apply — ACM validation will now complete
#
# Until then, this file is written but its resources are wrapped in
# a count guard so `terraform apply` across the rest of global/ won't
# fail or hang because of this one piece.
# =============================================================

locals {
  # 0 resources created if no domain set yet, 1 once it is — lets the
  # rest of global/ (state backend, ECR) apply independently.
  dns_enabled = var.root_domain != "" ? 1 : 0
}

resource "aws_route53_zone" "main" {
  count = local.dns_enabled
  name  = var.root_domain

  tags = merge(local.tags, { Name = var.root_domain })
}

resource "aws_acm_certificate" "wildcard" {
  count                     = local.dns_enabled
  domain_name               = var.root_domain
  subject_alternative_names = ["*.${var.root_domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.tags, { Name = var.root_domain })
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.dns_enabled == 1 ? {
    for dvo in aws_acm_certificate.wildcard[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id = aws_route53_zone.main[0].zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "wildcard" {
  count                   = local.dns_enabled
  certificate_arn         = aws_acm_certificate.wildcard[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

output "hosted_zone_id" {
  value       = local.dns_enabled == 1 ? aws_route53_zone.main[0].zone_id : null
  description = "Pass this to each env's Helm/ingress config once a real domain is set"
}

output "name_servers" {
  value       = local.dns_enabled == 1 ? aws_route53_zone.main[0].name_servers : []
  description = "Copy these into your domain registrar's nameserver settings"
}

output "wildcard_certificate_arn" {
  value       = local.dns_enabled == 1 ? aws_acm_certificate_validation.wildcard[0].certificate_arn : null
  description = "Pass this to the ALB Controller / ingress annotations in each env for HTTPS"
}