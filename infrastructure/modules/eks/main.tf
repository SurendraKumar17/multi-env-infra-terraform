

# ─────────────────────────────────────────
# Allow the shared ALB to reach pods for health checks and traffic
# Without this, the ALB times out trying to reach any pod IP —
# its own security group only controls internet→ALB traffic, not
# ALB→node traffic.
# ─────────────────────────────────────────
resource "aws_security_group_rule" "allow_alb_to_nodes" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  source_security_group_id = var.alb_security_group_id
  description               = "Allow ALB (health checks + traffic) to reach pods on any port"
}