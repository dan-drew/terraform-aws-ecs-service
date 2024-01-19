locals {
  role_count = var.role_policy == null ? 0 : 1
  role_arn = try(
    concat(
      var.role_arn == null ? [] : [var.role_arn],
      aws_iam_role.service.*.arn
    )[0],
    null
  )
}

module "ecs_task_assume_role" {
  source = "github.com/tfext/terraform-aws-assume-role-policy"
  type   = "ecs_task"
}

resource "aws_iam_role" "service" {
  count              = local.role_count
  name               = var.name
  path               = "/service/"
  assume_role_policy = module.ecs_task_assume_role.policy.json
}

resource "aws_iam_policy" "service" {
  count  = local.role_count
  name   = var.name
  policy = var.role_policy
}

resource "aws_iam_role_policy_attachment" "service" {
  count      = local.role_count
  policy_arn = aws_iam_policy.service[0].arn
  role       = aws_iam_role.service[0].name
}
