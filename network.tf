locals {
  lb_enabled          = length(var.load_balancers) > 0
  service_type        = var.containers[0].service_type
  is_alb              = local.lb_enabled && local.service_type == "http"
  is_nlb              = local.lb_enabled && !local.is_alb
  target_group_prefix = coalesce(var.target_group_prefix, var.name)
  lbs                 = { for lb in var.load_balancers : lb.name => lb }

  default_health_check = {
    enabled      = true
    path         = "/"
    status_codes = "200-399"
    threshold    = 5
    interval     = 120
    timeout      = 10
  }

  ports = local.lb_enabled ? merge(
    [
      for c in var.containers : c.ports == null ? {} : {
        for p in c.ports : coalesce(p.public_port, p.port) => {
          port           = coalesce(p.public_port, p.port)
          container_port = p.port
          container_name = c.container_name
          health_check = merge(
            local.default_health_check,
            { for k, v in coalesce(p.health_check, {}) : k => v if v != null }
          )
        }
      }
    ]...
  ) : null

  # Uber list of ports x load balancers
  lb_ports = local.ports != null ? merge([
    for lb in var.load_balancers : {
      for p, port in coalesce(local.ports, {}) :
      "${lb.name}-${p}" => merge(
        lb,
        port,
        {
          prefix         = "${coalesce(lb.short_name, lb.name)}-${p}"
          lb             = data.aws_lb.lb[lb.name]
          vpc            = data.aws_vpc.lb_vpc[lb.name]
          container_name = port.container_name
        }
      ) if try(contains(lb.ports, p), true)
    }
  ]...) : {}
}

data "aws_vpc" "lb_vpc" {
  for_each = local.lbs
  tags     = { "Name" = each.value.vpc }
}

data "aws_lb" "lb" {
  for_each = local.lbs
  name     = each.value.name
}

data "aws_lb_listener" "listener" {
  for_each          = local.is_alb ? local.lb_ports : {}
  load_balancer_arn = each.value.lb.arn
  port              = each.value.port
}

data "aws_route53_zone" "dns_zone" {
  for_each = local.lbs
  name     = each.value.dns_zone
}

resource "aws_lb_target_group" "service" {
  for_each = local.lb_ports
  name = join("-", [
    local.target_group_prefix,
    each.value.prefix,
    module.aws_utils.timestamp
  ])
  port                          = each.value.container_port
  protocol                      = upper(local.service_type)
  vpc_id                        = each.value.vpc.id
  depends_on                    = [aws_ecs_task_definition.service]
  load_balancing_algorithm_type = "least_outstanding_requests"
  deregistration_delay          = 30

  # This is true by default for target groups in an NLB, but causes issues when containers
  # try to talk to other containers on the same host (presumably because the host thinks it's
  # talking to itself).
  # Note that disabling this is only supported for TCP-only services.
  # https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-target-groups.html#client-ip-preservation
  preserve_client_ip = local.is_alb ? null : false

  # ALB Health Check
  dynamic "health_check" {
    for_each = local.is_alb && each.value.health_check.enabled ? [1] : []
    content {
      healthy_threshold = each.value.health_check.threshold
      interval          = each.value.health_check.interval
      timeout           = each.value.health_check.timeout
      path              = each.value.health_check.path
      matcher           = each.value.health_check.status_codes
      port              = "traffic-port"
    }
  }

  dynamic "health_check" {
    for_each = local.is_alb && !each.value.health_check.enabled ? [1] : []
    content {
      enabled = false
    }
  }

  # NLB
  dynamic "health_check" {
    for_each = local.is_nlb ? [1] : []
    content {
      protocol            = "TCP"
      interval            = 30
      port                = "traffic-port"
      healthy_threshold   = 2
      unhealthy_threshold = 2
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [name]
  }
}

resource "aws_lb_listener_rule" "http_listener" {
  for_each     = local.is_alb ? local.lb_ports : {}
  listener_arn = data.aws_lb_listener.listener[each.key].arn
  priority     = each.value.priority

  action {
    target_group_arn = aws_lb_target_group.service[each.key].arn
    type             = "forward"
  }

  condition {
    host_header { values = ["${each.value.dns_subdomain}.*"] }
  }
}

resource "aws_lb_listener" "tcp_target" {
  for_each          = local.is_nlb ? local.ports : {}
  load_balancer_arn = data.aws_lb.lb[0].arn
  port              = each.value.port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service[each.key].arn
  }
}

resource "aws_route53_record" "service" {
  for_each = local.lbs
  zone_id  = data.aws_route53_zone.dns_zone[each.key].zone_id
  name     = each.value.dns_subdomain
  type     = "A"

  alias {
    evaluate_target_health = false
    name                   = data.aws_lb.lb[each.key].dns_name
    zone_id                = data.aws_lb.lb[each.key].zone_id
  }

  depends_on = [aws_ecs_service.service]
}
