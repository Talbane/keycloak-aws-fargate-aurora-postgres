resource "aws_security_group" "vpc_endpoints" {
  count = var.create_vpc_endpoints ? 1 : 0

  name        = "${local.name}-vpce"
  description = "Private AWS service endpoints used by Keycloak Fargate tasks."
  vpc_id      = var.vpc_id

}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_from_ecs" {
  count = var.create_vpc_endpoints ? 1 : 0

  security_group_id            = aws_security_group.vpc_endpoints[0].id
  description                  = "HTTPS from Keycloak ECS tasks"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.ecs.id
}

resource "aws_vpc_security_group_egress_rule" "ecs_to_vpc_endpoints" {
  count = var.create_vpc_endpoints ? 1 : 0

  security_group_id            = aws_security_group.ecs.id
  description                  = "HTTPS to private AWS service endpoints"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.vpc_endpoints[0].id
}

locals {
  endpoint_services = toset(concat(
    ["ecr.api", "ecr.dkr", "logs", "secretsmanager"],
    var.enable_ecs_exec ? ["ssmmessages"] : []
  ))
}

resource "aws_vpc_endpoint" "interface" {
  for_each = var.create_vpc_endpoints ? local.endpoint_services : toset([])

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]

  tags = {
    Name = "${local.name}-${replace(each.value, ".", "-")}"
  }
}

resource "aws_vpc_endpoint" "s3" {
  count = var.create_vpc_endpoints && length(var.private_route_table_ids) > 0 ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = {
    Name = "${local.name}-s3"
  }
}

resource "aws_vpc_security_group_egress_rule" "ecs_to_s3_prefix_list" {
  count = var.create_vpc_endpoints ? 1 : 0

  security_group_id = aws_security_group.ecs.id
  description       = "HTTPS to S3 for ECR image layers through gateway endpoint"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_prefix_list.s3[0].id
}

check "private_ecr_path" {
  assert {
    condition     = !var.create_vpc_endpoints || length(var.private_route_table_ids) > 0
    error_message = "When create_vpc_endpoints=true, provide private_route_table_ids so ECR image layer downloads can use the S3 gateway endpoint without broad Internet egress."
  }
}
