module "vpc" {
  source             = "terraform-aws-modules/vpc/aws"
  version            = "2.31.0"
  name               = "${terraform.workspace}-omer-vpc"
  cidr               = var.cidr
  azs                = var.azs
  private_subnets    = var.private_subnets
  public_subnets     = var.public_subnets
  enable_nat_gateway = true
  enable_vpn_gateway = true
  tags               = local.tags

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"                 = 1
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
    "kubernetes.io/role/elb"                          = 1
  }

  vpc_tags = {
    Name                                              = "${terraform.workspace}-vpc"
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
  }
}

module "eks" {
  source       = "terraform-aws-modules/eks/aws"
  version      = "10.0.0"
  cluster_name = local.eks_cluster_name
  subnets      = module.vpc.private_subnets
  vpc_id       = module.vpc.vpc_id

  kubeconfig_aws_authenticator_env_variables = {
    AWS_PROFILE = var.aws_profile
  }

  worker_groups = [
    {
      name                 = "linux-workers"
      instance_type        = "t2.small"
      asg_desired_capacity = 2
    },
    # { 
    #   name                 = "windows-workers"
    #   instance_type        = "t2.medium"
    #   platform             = "windows"
    #   asg_desired_capacity = 1
    # },
    # {
    #   name                 = "gpu-workers"
    #   instance_type        = "p3.2xlarge"
    #   asg_desired_capacity = 1
    # },
  ]
}

module "mq" {
  source             = "jungopro/mq/aws"
  version            = "1.11.0"
  subnet_ids         = [element(module.vpc.private_subnets, 0)]
  security_group_ids = [module.vpc.default_security_group_id]
  vpc_id             = module.vpc.vpc_id

  rules = {
    allow_all_inbound = {
      type      = "ingress"
      protocol  = "tcp"
      from_port = "0"
      to_port   = "0"
      cidr_blocks = [
        "0.0.0.0/0",
      ]
    }
  }
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "2.14.0"

  identifier = "demodb"

  engine            = "sqlserver-ex"
  engine_version    = "14.00.1000.169.v1"
  instance_class    = "db.t2.medium"
  allocated_storage = 20
  storage_encrypted = false

  name     = null
  username = "demouser"
  password = "YourPwdShouldBeLongAndSecure!"
  port     = "1433"

  vpc_security_group_ids = [module.vpc.default_security_group_id]

  maintenance_window = "Mon:00:00-Mon:03:00"
  backup_window      = "03:00-06:00"

  # disable backups to create DB faster
  backup_retention_period = 0

  tags = {
    Owner       = "user"
    Environment = "dev"
  }

  # DB subnet group
  subnet_ids = module.vpc.private_subnets

  # Snapshot name upon DB deletion
  final_snapshot_identifier = "demodb"

  create_db_parameter_group = false
  license_model             = "license-included"

  timezone = "Central Standard Time"

  # Database Deletion Protection
  deletion_protection = false

  # DB options
  major_engine_version = "14.00"

  options = []
}

resource "kubernetes_secret" "cloud_config" {
  metadata {
    name      = "cloud-config"
    namespace = "default"
  }

  data = {
    mq_broker_ssl_endpoint = module.mq.aws_mq_broker.instances[0].endpoints[0]
    sql_username           = module.rds.this_db_instance_username
    sql_password           = module.rds.this_db_instance_password
    sql_endpoint           = module.rds.this_db_instance_endpoint
  }
}

resource "helm_release" "ingress_controller" {
  name      = "nginx-ingress"
  namespace = "kube-system"
  chart     = "../community_charts/nginx-ingress"
  values = [
    file("../community_charts/nginx-ingress/values.yaml")
  ]
}
