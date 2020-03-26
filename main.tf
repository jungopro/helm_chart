variable "creds_file_path" {
  description = "path to aws creds file"
  default = "/Users/omerbarel/.aws/credentials"
}

variable "aws_profile" {
  description = "aws profile name as specified in file in var.creds_file_path"
  default = "default"
}

provider "aws" {
  version                 = "~> 2.0"
  region                  = "eu-west-2"
  shared_credentials_file = var.creds_file_path
  profile                 = var.aws_profile
}

variable "tags" {
  type        = map(string)
  description = "list of tags to apply to the resource"
  default     = {}
}

locals {
  eks_cluster_name = "omer-${terraform.workspace}-cluster"
  tags             = "${merge("${var.tags}", map("terraform workspace", "${terraform.workspace}"), map("environment", "${terraform.workspace}"))}"
}

## first build pipeline

module "vpc" {
  source             = "terraform-aws-modules/vpc/aws"
  version            = "2.31.0"
  name               = "${terraform.workspace}-omer-vpc"
  cidr               = "10.0.0.0/16"
  azs                = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
  private_subnets    = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
  public_subnets     = ["10.0.96.0/20", "10.0.112.0/20", "10.0.128.0/20"]
  enable_nat_gateway = true
  enable_vpn_gateway = true
  tags               = local.tags

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"                 = 1
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
  }

  vpc_tags = {
    Name                                              = "${terraform.workspace}-vpc"
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
  }
}

## second build pipeline. use data source to retrieve vpc data

module "eks" {
  source       = "terraform-aws-modules/eks/aws"
  version      = "10.0.0"
  cluster_name = local.eks_cluster_name
  subnets      = module.vpc.private_subnets
  vpc_id       = module.vpc.vpc_id

  kubeconfig_aws_authenticator_env_variables = {
    AWS_PROFILE = "default"
  }

  worker_groups = [
    {
      name                 = "linux-workers"
      instance_type        = "t2.small"
      asg_desired_capacity = 1
    },
    {
      name                 = "windows-workers"
      instance_type        = "t2.medium"
      platform             = "windows"
      asg_desired_capacity = 1
    },
    # {
    #   name                 = "gpu-workers"
    #   instance_type        = "p3.2xlarge"
    #   asg_desired_capacity = 1
    # },
  ]
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
  version                = "~> 1.9"
}

## third build pipeline. use data source to retrieve vpc data

module "mq" {
  source             = "jungopro/mq/aws"
  version            = "1.11.0"
  subnet_ids         = [element(module.vpc.private_subnets, 0)]
  security_group_ids = [module.vpc.default_security_group_id]
  vpc_id             = module.vpc.vpc_id
  
  rules = {
    allow_all_inbound = {
      type        = "ingress"
      protocol    = "tcp"
      from_port   = "0"
      to_port     = "0"
      cidr_blocks = [
        "0.0.0.0/0",
      ]
    }
  }
}

## fourth build pipeline. use data source to retrieve vpc data

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "2.14.0"

  identifier = "demodb"

  engine            = "sqlserver-ex"
  engine_version    = "14.00.1000.169.v1"
  instance_class    = "db.t2.medium"
  allocated_storage = 20
  storage_encrypted = false

  name     = null # "demodb"
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

## fifth build pipeline. use data source to retrieve k8s data

resource "kubernetes_secret" "cloud_config" {
  metadata {
    name      = "cloud-config"
    namespace = "default"
  }

  data = {
    mq_broker_ssl_endpoint = module.mq.aws_mq_broker.instances[0].endpoints[0]
  } 
}
