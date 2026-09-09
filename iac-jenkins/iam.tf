resource "aws_iam_role" "jenkins_role" {
  name = "jenkins-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "jenkins-ec2-profile"
  role = aws_iam_role.jenkins_role.name
}

# Lets the Jenkinsfile authenticate to and push into per-service ECR Public
# repos using this instance's role credentials, so no static AWS access keys
# ever need to be stored in Jenkins or referenced in this public repo.
resource "aws_iam_role_policy" "jenkins_ecr_public" {
  name = "jenkins-ecr-public-push"
  role = aws_iam_role.jenkins_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # `aws ecr-public get-login-password` is checked against both
        # ecr-public:GetAuthorizationToken (granted below) and this STS
        # permission for the underlying bearer-token exchange. Granted
        # unconditionally (no sts:AWSServiceName restriction) since the
        # exact required condition value wasn't reliably verifiable and
        # this role is already scoped to this one CI purpose.
        Sid      = "EcrPublicAuth"
        Effect   = "Allow"
        Action   = "sts:GetServiceBearerToken"
        Resource = "*"
      },
      {
        Sid    = "EcrPublicPush"
        Effect = "Allow"
        Action = [
          "ecr-public:GetAuthorizationToken",
          "ecr-public:DescribeRepositories",
          "ecr-public:CreateRepository",
          "ecr-public:BatchCheckLayerAvailability",
          "ecr-public:InitiateLayerUpload",
          "ecr-public:UploadLayerPart",
          "ecr-public:CompleteLayerUpload",
          "ecr-public:PutImage",
        ]
        Resource = "*"
      },
    ]
  })
}
