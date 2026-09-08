output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}

output "jenkins_url" {
  value = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "key_pair_name" {
  value = aws_key_pair.jenkins_key.key_name
}

output "private_key_path" {
  description = "Local path to the generated SSH private key (gitignored, not committed)"
  value       = local_file.jenkins_private_key.filename
}

output "private_key_pem" {
  description = "SSH private key material. Marked sensitive so it never prints in plain CI logs; run `terraform output -raw private_key_pem` to read it."
  value       = tls_private_key.jenkins_key.private_key_pem
  sensitive   = true
}

output "ssh_command" {
  value = "ssh -i ${local_file.jenkins_private_key.filename} ubuntu@${aws_instance.jenkins.public_ip}"
}
