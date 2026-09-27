resource "aws_ecs_cluster" "keycloak" {
  name = "${local.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "keycloak" {
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.ecs_cpu)
  memory                   = tostring(var.ecs_memory)
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "keycloak"
      image     = "${aws_ecr_repository.keycloak.repository_url}:${var.keycloak_image_tag}"
      essential = true

      command = ["start", "--optimized"]

      portMappings = [
        {
          name          = "http"
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
          appProtocol   = "http"
        },
        {
          name          = "management"
          containerPort = 9000
          hostPort      = 9000
          protocol      = "tcp"
          appProtocol   = "http"
        },
        {
          name          = "jgroups"
          containerPort = 7800
          hostPort      = 7800
          protocol      = "tcp"
        },
        {
          name          = "jgroups-fd"
          containerPort = 57800
          hostPort      = 57800
          protocol      = "tcp"
        }
      ]

      environment = [
        for key, value in local.task_environment : {
          name  = key
          value = value
        }
      ]

      secrets = concat(local.db_secrets, local.bootstrap_secrets)

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.keycloak.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "keycloak"
        }
      }

      stopTimeout = 30
    }
  ])
}

resource "aws_ecs_service" "keycloak" {
  name            = "${local.name}-service"
  cluster         = aws_ecs_cluster.keycloak.id
  task_definition = aws_ecs_task_definition.keycloak.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  enable_execute_command        = var.enable_ecs_exec
  enable_ecs_managed_tags       = true
  propagate_tags                = "SERVICE"
  availability_zone_rebalancing = "ENABLED"

  platform_version = "LATEST"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 180

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.internal.arn
    container_name   = "keycloak"
    container_port   = 8080
  }

  dynamic "load_balancer" {
    for_each = var.enable_external_alb ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.external[0].arn
      container_name   = "keycloak"
      container_port   = 8080
    }
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_lb_listener.internal_https,
    aws_lb_listener.external_https,
    aws_iam_role_policy.ecs_task_execution
  ]
}
