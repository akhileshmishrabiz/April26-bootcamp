variable "aws_region" {
  description = "AWS region used for the deployment."
  type        = string
  default     = "ap-south-1"
}

variable "app_name" {
  description = "Prefix used for resource names."
  type        = string
  default     = "devsecops-training"
}

variable "container_image" {
  description = "Container image URI, for example an ECR image URI."
  type        = string
}

variable "container_port" {
  description = "Port exposed by the Flask container."
  type        = number
  default     = 5000
}

variable "desired_count" {
  description = "Number of ECS tasks to run."
  type        = number
  default     = 1
}
