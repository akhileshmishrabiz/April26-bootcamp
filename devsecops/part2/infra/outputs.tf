output "load_balancer_url" {
  description = "Public URL of the application load balancer."
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.app.name
}
