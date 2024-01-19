locals {
  target_metric_map = {
    requests = "ALBRequestCountPerTarget"
    memory   = "ECSServiceAverageMemoryUtilization"
    cpu      = "ECSServiceAverageCPUUtilization"
  }
}

resource "aws_appautoscaling_target" "service" {
  count              = var.target_scaling != null || var.custom_scaling ? 1 : 0
  max_capacity       = var.scaling_options.max
  min_capacity       = var.scaling_options.min
  resource_id        = "service/${regex("[^\\/]+$", data.aws_ecs_cluster.cluster.id)}/${var.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "track_requests" {
  count              = try(var.target_scaling.metric, null) == "requests" ? 1 : 0
  name               = "${var.name}-policy"
  resource_id        = aws_appautoscaling_target.service.0.resource_id
  scalable_dimension = aws_appautoscaling_target.service.0.scalable_dimension
  service_namespace  = aws_appautoscaling_target.service.0.service_namespace
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value       = var.target_scaling.target
    scale_in_cooldown  = var.scaling_options.scale_down_delay
    scale_out_cooldown = var.scaling_options.scale_up_delay

    predefined_metric_specification {
      predefined_metric_type = local.target_metric_map[var.target_scaling.metric]
      resource_label         = "${data.aws_lb.lb.0.arn_suffix}/${aws_lb_target_group.service.0.arn_suffix}"
    }
  }
}

resource "aws_appautoscaling_policy" "track_cpu_memory" {
  count              = (var.target_scaling != null) && (try(var.target_scaling.metric, null) != "requests") ? 1 : 0
  name               = "${var.name}-policy"
  resource_id        = aws_appautoscaling_target.service.0.resource_id
  scalable_dimension = aws_appautoscaling_target.service.0.scalable_dimension
  service_namespace  = aws_appautoscaling_target.service.0.service_namespace
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value       = var.target_scaling.target
    scale_in_cooldown  = 300
    scale_out_cooldown = 30

    predefined_metric_specification {
      predefined_metric_type = local.target_metric_map[var.target_scaling.metric]
    }
  }
}
