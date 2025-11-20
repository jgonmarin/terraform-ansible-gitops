variable "aws_region" {
    description = "AWS Region where the resources will be deployed"
    type        = string
    default     = "us-east-2" 
}

variable "instance_type" {
  description = "EC2 Instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Key Pair Name"
  type        = string
  default     = "clave_ssh_jg"
}

variable "vpc_cidr" {
  description = "CIDR for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "project_tag" {
    description = "Project identifier label"
    type        = string
    default     = "StaticWebsiteProject"
}