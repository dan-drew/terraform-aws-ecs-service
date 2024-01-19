module aws_utils {
  source = "github.com/tfext/terraform-aws-base"
}

data aws_ecs_cluster cluster {
  cluster_name = var.cluster
}
