# Auto-detect the machine running `terraform apply` so SSH access is
# scoped to it by default instead of requiring manual input or opening
# the port to the world.
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  effective_ssh_cidr = coalesce(var.allowed_ssh_cidr, "${chomp(data.http.my_ip.response_body)}/32")
}

# Pinned explicitly (rather than deriving the volume's AZ from the instance,
# or vice versa) so the instance and its data volume don't depend on each
# other for AZ placement, which caused a dependency cycle when combined with
# resource replacement.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az = data.aws_availability_zones.available.names[0]
}
