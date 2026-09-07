
resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins_profile.name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -eux

    # Latest Amazon Corretto (OpenJDK) 21 LTS
    dnf install -y java-21-amazon-corretto

    # Official Jenkins repo — always installs latest Jenkins release
    wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
    dnf install -y jenkins

    # Wait for the EBS volume attachment (created after this instance exists,
    # so it is not guaranteed to be present the instant user_data starts)
    for i in $(seq 1 30); do
      [ -e /dev/xvdf ] && break
      sleep 5
    done

    # Format only if the volume has no filesystem yet (avoids wiping data
    # on instance replacement when the same EBS volume is reattached)
    if ! blkid /dev/xvdf; then
      mkfs -t xfs /dev/xvdf
    fi

    mkdir -p /var/lib/jenkins
    echo "/dev/xvdf /var/lib/jenkins xfs defaults,nofail 0 2" >> /etc/fstab
    mount /var/lib/jenkins
    chown -R jenkins:jenkins /var/lib/jenkins

    systemctl enable jenkins
    systemctl start jenkins
  EOF

  tags = {
    Name = "jenkins-server"
  }
}
