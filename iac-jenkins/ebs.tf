# Separate persistent volume for JENKINS_HOME, decoupled from instance lifecycle
resource "aws_ebs_volume" "jenkins_home" {
  availability_zone = aws_instance.jenkins.availability_zone
  size              = var.jenkins_home_volume_size
  type              = "gp3"

  tags = {
    Name = "jenkins-home"
  }
}

resource "aws_volume_attachment" "jenkins_home_attach" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.jenkins_home.id
  instance_id = aws_instance.jenkins.id
}
