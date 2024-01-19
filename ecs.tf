locals {
  container_definitions = var.containers.*.definition
  min_healthy           = var.singleton ? 0 : 100
  max_healthy           = var.singleton ? 100 : 200
}

resource "aws_ecs_task_definition" "service" {
  family                = var.name
  container_definitions = jsonencode(local.container_definitions)
  task_role_arn         = local.role_arn
  depends_on            = [aws_iam_role_policy_attachment.service]

  dynamic "volume" {
    for_each = { for def in var.containers : def.shared_data.volume => def.shared_data if def.shared_data != null }
    content {
      name = volume.key

      efs_volume_configuration {
        file_system_id          = volume.value.efs_id
        transit_encryption      = "ENABLED"
        authorization_config {
          access_point_id = volume.value.access_point_id
          iam             = "ENABLED"
        }
      }
    }
  }
}

resource "aws_ecs_service" "service" {
  name                               = var.name
  task_definition                    = aws_ecs_task_definition.service.arn
  desired_count                      = 1
  deployment_minimum_healthy_percent = local.min_healthy
  deployment_maximum_percent         = local.max_healthy
  cluster                            = data.aws_ecs_cluster.cluster.id
  launch_type                        = "EC2"
  wait_for_steady_state              = var.wait_for_stable
  propagate_tags                     = "SERVICE"

  dynamic "load_balancer" {
    for_each = local.lb_ports
    iterator = target
    content {
      target_group_arn = aws_lb_target_group.service[target.key].arn
      container_name   = coalesce(target.value.container_name, var.name)
      container_port   = target.value.container_port
    }
  }

  # Always spread container instances across zones and instances
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "instanceId"
  }

  dynamic "placement_constraints" {
    for_each = var.singleton ? ["distinct"] : []
    content {
      type = "distinctInstance"
    }
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener_rule.http_listener, aws_lb_listener.tcp_target]

  lifecycle {
    ignore_changes = [desired_count]
  }
}
