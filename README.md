ecs_service
===========

Variables
---------

### General

| Variable                | Type     | Default | Description                                     |
|-------------------------|----------|---------|-------------------------------------------------|
| `name`                  | `string` | -       | Service name                                    |
| `cluster_id`            | `string` | -       | ECS cluster to host the service                 |
| `container_definitions` | `string` | -       | Service container definitions                   |
| `create_log_group`      | `bool`   | `true`  | **_All new services should set this to false_** |

### Networking

| Variable           | Type     | Default | Description                                                                |
|--------------------|----------|---------|----------------------------------------------------------------------------|
| `service_port`     | `number` | 80      | Container's service port, if applicable. Ignored if no LB params provided. |
| `service_protocol` | `string` | `null`  | Service protocol (defaults to HTTP if ALB provided or TCP for NLB)         |
| `lb_listener_arn`  | `string` | `null`  | Register as an HTTP service on an ALB listener                             |
| `network_lb_arn`   | `string` | `null`  | Register as a non-HTTP service on an NLB                                   | 
| `dns_zone_id`      | `string` | `null`  | Route53 zone ID to register the service in                                 |
| `dns_subdomain`    | `string` | `null`  | Subdomain to register service as (required if `dns_zone_id`)               |

### Deployment

All services are configured to spread evenly across AZs and hosts

| Variable            | Type   | Default | Description                                                                      |
|---------------------|--------|---------|----------------------------------------------------------------------------------|
| `distinct_instance` | `bool` | `false` | If set to true, will prevent multiple containers being deployed on the same host |

### Scaling

These options enable auto-scaling for the service.

#### Target-based scaling

ECS will scale up or down to keep the metric near the desired target 

| Variable                | Type     | Default | Description                                                |
|-------------------------|----------|---------|------------------------------------------------------------|
| `target_scaling`        | `object` | `null`  | Enables scaling based on a target metric                   |
| `target_scaling.metric` | `string` | -       | One of the following values: `requests`, `cpu` or `memory` |
| `target_scaling.target` | `number` | -       | The desired target value                                   |

```
module my_service {
  ...
  target_scaling = { metric = "requests", target = 100 }
}
```

#### Custom scaling

Caller is responsible for creating an appropriate step-based scale strategy
referencing the `scaling_target` output variable.

```
module my_service {
  ...
  custom_scaling = true
}

resource "aws_appautoscaling_policy" "ecs_policy" {
  name               = "my-policy-name"
  policy_type        = "StepScaling"
  resource_id        = module.my_service.output.scaling_target.resource_id
  scalable_dimension = module.my_service.output.scaling_target.scalable_dimension
  service_namespace  = module.my_service.output.scaling_target.service_namespace

  step_scaling_policy_configuration {
    ...
  }
} 
```

| Variable         | Type   | Default | Description                                   |
|------------------|--------|---------|-----------------------------------------------|
| `custom_scaling` | `bool` | `false` | Enables creation of the scaling policy target |

#### Scaling options

Common scaling options

| Variable                           | Type     | Default | Description                                                        |
|------------------------------------|----------|---------|--------------------------------------------------------------------|
| `scaling_options`                  | `object` |         | Set to override default scaling parameters                         |
| `scaling_options.min`              | `number` | 1       | Minimum number of containers                                       |
| `scaling_options.max`              | `number` | 20      | Maximum number of containers                                       |
| `scaling_options.scale_down_delay` | `number` | 300     | Number of seconds before ECS will consider a new scale down action |
| `scaling_options.scale_up_delay`   | `number` | 30      | Number of seconds before ECS will consider a new scale up action   |

```
module my_service {
  ...
  scaling_options = { min = 5, max = 20, scale_down_delay = 45, scale_up_delay = 10 }
}
```

