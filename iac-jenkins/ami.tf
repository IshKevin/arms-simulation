# Always resolves to the latest official Ubuntu 24.04 LTS AMI via
# Canonical/AWS's published SSM parameter (updated automatically upstream).
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}
