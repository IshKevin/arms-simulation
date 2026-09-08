variable "aws_region" {
  default = "eu-west-1"
}

variable "instance_type" {
  default = "t3.medium"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH. Leave null to auto-detect and restrict to the machine running terraform apply."
  type        = string
  default     = null
}

variable "allowed_jenkins_cidr" {
  description = "CIDR allowed to access Jenkins UI"
  type        = string
  default     = "0.0.0.0/0"
}

variable "root_volume_size" {
  default = 30
}

variable "jenkins_home_volume_size" {
  default = 50
}
