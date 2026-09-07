variable "aws_region" {
  default = "us-east-1"
}

variable "instance_type" {
  default = "t3.medium"
}

variable "key_name" {
  description = "Existing EC2 key pair name for SSH access"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH (restrict this, do not leave 0.0.0.0/0)"
  type        = string
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
