resource "aws_security_group" "ecs" {
  name        = "${local.name}-ecs"
  description = "Keycloak Fargate tasks; ingress only from ALBs and cluster peers."
  vpc_id      = var.vpc_id

}

resource "aws_security_group" "internal_alb" {
  name        = "${local.name}-alb-int"
  description = "Internal Keycloak ALB."
  vpc_id      = var.vpc_id

}

resource "aws_security_group" "external_alb" {
  count = var.enable_external_alb ? 1 : 0

  name        = "${local.name}-alb-ext"
  description = "External/split-DNS Keycloak ALB."
  vpc_id      = var.vpc_id

}

resource "aws_vpc_security_group_ingress_rule" "internal_alb_https_v4" {
  for_each = toset(var.internal_alb_ingress_cidrs)

  security_group_id = aws_security_group.internal_alb.id
  description       = "Trusted internal client HTTPS"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "internal_alb_https_v6" {
  for_each = toset(var.internal_alb_ingress_ipv6_cidrs)

  security_group_id = aws_security_group.internal_alb.id
  description       = "Trusted internal client HTTPS IPv6"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "external_alb_https_v4" {
  for_each = var.enable_external_alb ? toset(var.external_alb_ingress_cidrs) : toset([])

  security_group_id = aws_security_group.external_alb[0].id
  description       = "Approved external client HTTPS"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "external_alb_https_v6" {
  for_each = var.enable_external_alb ? toset(var.external_alb_ingress_ipv6_cidrs) : toset([])

  security_group_id = aws_security_group.external_alb[0].id
  description       = "Approved external client HTTPS IPv6"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = each.value
}

resource "aws_vpc_security_group_egress_rule" "internal_alb_to_keycloak_http" {
  security_group_id            = aws_security_group.internal_alb.id
  description                  = "ALB to Keycloak application port"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.ecs.id
}

resource "aws_vpc_security_group_egress_rule" "internal_alb_to_keycloak_health" {
  security_group_id            = aws_security_group.internal_alb.id
  description                  = "ALB readiness checks to Keycloak management port"
  ip_protocol                  = "tcp"
  from_port                    = 9000
  to_port                      = 9000
  referenced_security_group_id = aws_security_group.ecs.id
}

resource "aws_vpc_security_group_egress_rule" "external_alb_to_keycloak_http" {
  count = var.enable_external_alb ? 1 : 0

  security_group_id            = aws_security_group.external_alb[0].id
  description                  = "External ALB to Keycloak application port"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.ecs.id
}

resource "aws_vpc_security_group_egress_rule" "external_alb_to_keycloak_health" {
  count = var.enable_external_alb ? 1 : 0

  security_group_id            = aws_security_group.external_alb[0].id
  description                  = "External ALB readiness checks to Keycloak management port"
  ip_protocol                  = "tcp"
  from_port                    = 9000
  to_port                      = 9000
  referenced_security_group_id = aws_security_group.ecs.id
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_internal_alb_http" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Keycloak app traffic only from internal ALB"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.internal_alb.id
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_internal_alb_health" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Keycloak health traffic only from internal ALB"
  ip_protocol                  = "tcp"
  from_port                    = 9000
  to_port                      = 9000
  referenced_security_group_id = aws_security_group.internal_alb.id
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_external_alb_http" {
  count = var.enable_external_alb ? 1 : 0

  security_group_id            = aws_security_group.ecs.id
  description                  = "Keycloak app traffic only from external ALB"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.external_alb[0].id
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_external_alb_health" {
  count = var.enable_external_alb ? 1 : 0

  security_group_id            = aws_security_group.ecs.id
  description                  = "Keycloak health traffic only from external ALB"
  ip_protocol                  = "tcp"
  from_port                    = 9000
  to_port                      = 9000
  referenced_security_group_id = aws_security_group.external_alb[0].id
}

resource "aws_vpc_security_group_ingress_rule" "ecs_jgroups_7800" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Keycloak JGroups cluster transport from peer tasks"
  ip_protocol                  = "tcp"
  from_port                    = 7800
  to_port                      = 7800
  referenced_security_group_id = aws_security_group.ecs.id
}

resource "aws_vpc_security_group_ingress_rule" "ecs_jgroups_57800" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Keycloak JGroups failure detection from peer tasks"
  ip_protocol                  = "tcp"
  from_port                    = 57800
  to_port                      = 57800
  referenced_security_group_id = aws_security_group.ecs.id
}

resource "aws_vpc_security_group_egress_rule" "ecs_jgroups_7800" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Keycloak JGroups cluster transport to peer tasks"
  ip_protocol                  = "tcp"
  from_port                    = 7800
  to_port                      = 7800
  referenced_security_group_id = aws_security_group.ecs.id
}

resource "aws_vpc_security_group_egress_rule" "ecs_jgroups_57800" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Keycloak JGroups failure detection to peer tasks"
  ip_protocol                  = "tcp"
  from_port                    = 57800
  to_port                      = 57800
  referenced_security_group_id = aws_security_group.ecs.id
}

resource "aws_vpc_security_group_egress_rule" "ecs_https_v4" {
  for_each = toset(var.https_egress_cidrs)

  security_group_id = aws_security_group.ecs.id
  description       = "Explicit Keycloak HTTPS egress"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "ecs_https_v6" {
  for_each = toset(var.https_egress_ipv6_cidrs)

  security_group_id = aws_security_group.ecs.id
  description       = "Explicit Keycloak HTTPS egress IPv6"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv6         = each.value
}

resource "aws_vpc_security_group_egress_rule" "ecs_https_prefix_lists" {
  for_each = toset(var.https_egress_prefix_list_ids)

  security_group_id = aws_security_group.ecs.id
  description       = "Explicit Keycloak HTTPS egress to prefix list"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = each.value
}

resource "aws_vpc_security_group_egress_rule" "ecs_https_security_groups" {
  for_each = toset(var.https_egress_security_group_ids)

  security_group_id            = aws_security_group.ecs.id
  description                  = "Explicit Keycloak HTTPS egress to destination SG"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_egress_rule" "ecs_additional_cidr" {
  for_each = { for i, rule in var.additional_egress_cidr_rules : tostring(i) => rule }

  security_group_id = aws_security_group.ecs.id
  description       = each.value.description
  ip_protocol       = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  cidr_ipv4         = each.value.cidr_ipv4
}

resource "aws_vpc_security_group_egress_rule" "ecs_additional_security_group" {
  for_each = { for i, rule in var.additional_egress_security_group_rules : tostring(i) => rule }

  security_group_id            = aws_security_group.ecs.id
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  referenced_security_group_id = each.value.security_group_id
}
