resource "aws_instance" "jenkins" {
  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = var.instance_type
  availability_zone      = local.az
  key_name               = aws_key_pair.jenkins_key.key_name
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins_profile.name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -eux

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y fdisk wget gnupg xfsprogs unzip curl python3-venv python3-pip docker.io

    # Latest OpenJDK 21 LTS
    apt-get install -y openjdk-21-jdk

    systemctl enable --now docker
    usermod -aG docker jenkins

    # Helm (official installer, always latest stable)
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    # kubeconform (latest release binary)
    KUBECONFORM_VERSION=$(curl -fsSL https://api.github.com/repos/yannh/kubeconform/releases/latest | grep -oP '"tag_name": "\K[^"]+')
    curl -fsSL "https://github.com/yannh/kubeconform/releases/download/$${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz" | tar -xz -C /usr/local/bin kubeconform

    # yq (latest release binary)
    YQ_VERSION=$(curl -fsSL https://api.github.com/repos/mikefarah/yq/releases/latest | grep -oP '"tag_name": "\K[^"]+')
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/$${YQ_VERSION}/yq_linux_amd64" -o /usr/local/bin/yq
    chmod +x /usr/local/bin/yq

    # AWS CLI v2
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    (cd /tmp && unzip -q awscliv2.zip && ./aws/install)
    rm -rf /tmp/aws /tmp/awscliv2.zip

    # Official Jenkins apt repo. Jenkins rotates this signing key periodically
    # (the filename's year is the expiry) — check jenkins.io/doc/book/installing/linux
    # if apt-get update ever reports NO_PUBKEY again after this key expires.
    wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
      > /etc/apt/sources.list.d/jenkins.list
    apt-get update -y
    apt-get install -y jenkins

    # Wait for the EBS volume attachment (created after this instance exists,
    # so it is not guaranteed to be present the instant user_data starts),
    # then find it dynamically. Nitro instances expose EBS volumes as NVMe
    # devices (e.g. /dev/nvme1n1), not the /dev/xvdf name given at attach
    # time, and the exact device node isn't knowable in advance — so find
    # whichever nvme*n1 disk is NOT the root disk, at runtime.
    device=""
    root_disk="/dev/$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)")"
    for i in $(seq 1 30); do
      for d in /dev/nvme*n1; do
        if [ "$d" != "$root_disk" ]; then
          device="$d"
          break 2
        fi
      done
      sleep 5
    done
    if [ -z "$device" ]; then
      echo "ERROR: data disk not found" >&2
      exit 1
    fi

    # Format only if the volume has no filesystem yet (avoids wiping data
    # on instance replacement when the same EBS volume is reattached)
    if ! blkid "$device"; then
      mkfs -t xfs "$device"
    fi

    # Use the filesystem UUID (not the raw device path) in fstab, since
    # /dev/nvmeXnY ordering is not guaranteed stable across reboots.
    uuid=$(blkid -s UUID -o value "$device")
    mkdir -p /var/lib/jenkins
    echo "UUID=$uuid /var/lib/jenkins xfs defaults,nofail 0 2" >> /etc/fstab
    mount /var/lib/jenkins
    chown -R jenkins:jenkins /var/lib/jenkins

    systemctl enable jenkins
    systemctl restart jenkins
  EOF

  tags = {
    Name = "jenkins-server"
  }
}
