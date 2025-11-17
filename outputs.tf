output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.techcorp_vpc.id
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.techcorp_alb.dns_name
}

output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = aws_eip.bastion_eip.public_ip
}

output "db_server_private_ip" {
  description = "Private IP address of database server"
  value       = aws_instance.db_server.private_ip
}

output "web_server_private_ips" {
  description = "Private IPs of web instances created by the Auto Scaling Group."
  value       = data.aws_instances.web_asg.private_ips

  # Note: when web instances are created by the ASG this value will populate.
  # It may be empty on the first `terraform apply` because the ASG launches
  # instances after Terraform finishes. To populate this output after apply
  # run `terraform refresh` (or run a second `terraform apply`) to update the
  # data source. See README for details about the two-step apply pattern.
}