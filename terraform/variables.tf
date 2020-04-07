## Variables

variable "creds_file_path" {
  description = "path to aws creds file"
  default     = "~/.aws/credentials"
}

variable "aws_profile" {
  description = "aws profile name as specified in file in var.creds_file_path"
  default     = "default"
}

variable "tags" {
  type        = map(string)
  description = "list of tags to apply to the resource"
  default     = {}
}

variable "cidr" {
  description = "CIDR for the VPC"
  default = "10.0.0.0/16"
}

variable "azs" {
  description = "list of AZs for the VPC"
  type = list(string)
  default = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
}

variable "private_subnets" {
  description = "list of private_subnets for the VPC"
  type = list(string)
  default = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
}

variable "public_subnets" {
  description = "list of public_subnets for the VPC"
  type = list(string)
  default = ["10.0.96.0/20", "10.0.112.0/20", "10.0.128.0/20"]
}