resource "aws_lb" "internal" {
  name               = "${local.name}-int"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.internal_alb.id]
  subnets            = local.internal_alb_subnets

  enable_deletion_protection = var.alb_deletion_protection
  drop_invalid_header_fields = true
  desync_mitigation_mode     = "defensive"
  idle_timeout               = 60
  xff_header_processing_mode = var.alb_xff_header_processing_mode

  dynamic "access_logs" {
    for_each = var.enable_alb_access_logs ? [1] : []
    content {
      bucket  = aws_s3_bucket.alb_logs[0].id
      prefix  = "${local.name}/internal"
      enabled = true
    }
  }

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

resource "aws_lb_target_group" "internal" {
  name        = substr("${local.name}-int-tg", 0, 32)
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "9000"
    path                = "/health/ready"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  stickiness {
    enabled         = true
    type            = "app_cookie"
    cookie_name     = "AUTH_SESSION_ID"
    cookie_duration = var.alb_stickiness_seconds
  }
}

resource "aws_lb_listener" "internal_https" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.alb_ssl_policy
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal.arn
  }
}

resource "aws_lb" "external" {
  count = var.enable_external_alb ? 1 : 0

  name               = "${local.name}-ext"
  internal           = var.external_alb_internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.external_alb[0].id]
  subnets            = local.external_alb_subnets

  enable_deletion_protection = var.alb_deletion_protection
  drop_invalid_header_fields = true
  desync_mitigation_mode     = "defensive"
  idle_timeout               = 60
  xff_header_processing_mode = var.alb_xff_header_processing_mode

  dynamic "access_logs" {
    for_each = var.enable_alb_access_logs ? [1] : []
    content {
      bucket  = aws_s3_bucket.alb_logs[0].id
      prefix  = "${local.name}/external"
      enabled = true
    }
  }

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

resource "aws_lb_target_group" "external" {
  count = var.enable_external_alb ? 1 : 0

  name        = substr("${local.name}-ext-tg", 0, 32)
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "9000"
    path                = "/health/ready"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  stickiness {
    enabled         = true
    type            = "app_cookie"
    cookie_name     = "AUTH_SESSION_ID"
    cookie_duration = var.alb_stickiness_seconds
  }
}

resource "aws_lb_listener" "external_https" {
  count = var.enable_external_alb ? 1 : 0

  load_balancer_arn = aws_lb.external[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.alb_ssl_policy
  certificate_arn   = var.acm_certificate_arn

  dynamic "default_action" {
    for_each = var.external_restrict_public_paths ? [1] : []
    content {
      type = "fixed-response"
      fixed_response {
        content_type = "text/plain"
        message_body = "Not Found"
        status_code  = "404"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.external_restrict_public_paths ? [] : [1]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.external[0].arn
    }
  }
}

resource "aws_lb_listener_rule" "external_public_paths" {
  count = var.enable_external_alb && var.external_restrict_public_paths ? 1 : 0

  listener_arn = aws_lb_listener.external_https[0].arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.external[0].arn
  }

  condition {
    path_pattern {
      values = ["/realms/*", "/resources/*", "/.well-known/*"]
    }
  }
}

resource "aws_lb_listener_rule" "external_block_admin" {
  count = var.enable_external_alb && var.external_block_admin_paths ? 1 : 0

  listener_arn = aws_lb_listener.external_https[0].arn
  priority     = 1

  action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }

  condition {
    path_pattern {
      values = ["/admin", "/admin/*", "/realms/master", "/realms/master/*"]
    }
  }
}

check "external_alb_inputs" {
  assert {
    condition = !var.enable_external_alb || (
      length(local.external_alb_subnets) >= 2 &&
      (length(var.external_alb_ingress_cidrs) + length(var.external_alb_ingress_ipv6_cidrs) > 0)
    )
    error_message = "When enable_external_alb=true, provide at least two external ALB subnets and at least one explicit ingress CIDR."
  }
}
