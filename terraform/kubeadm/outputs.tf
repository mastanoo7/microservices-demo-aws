output "cluster_name" {
  value = var.name
}

output "api_endpoint" {
  value = "https://${aws_lb.api.dns_name}:6443"
}

output "api_load_balancer_dns_name" {
  value = aws_lb.api.dns_name
}

output "control_plane_instance_ids" {
  value = aws_instance.control_plane[*].id
}

output "worker_autoscaling_group_name" {
  value = aws_autoscaling_group.worker.name
}

output "control_plane_role_arn" {
  value = aws_iam_role.control_plane.arn
}

output "worker_role_arn" {
  value = aws_iam_role.worker.arn
}

output "kubeconfig_ssm_parameter" {
  value = "${local.parameter_prefix}/admin-kubeconfig"
}

output "ssm_start_session_commands" {
  value = [
    for id in aws_instance.control_plane[*].id :
    "aws ssm start-session --target ${id} --region ${data.aws_region.current.region}"
  ]
}
