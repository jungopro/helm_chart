## Local Variables

locals {
  eks_cluster_name = "omer-${terraform.workspace}-cluster"
  tags             = "${merge("${var.tags}", map("terraform workspace", "${terraform.workspace}"), map("environment", "${terraform.workspace}"))}"
}