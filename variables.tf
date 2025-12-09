variable "project_name" {
  description = "Prefix for all resources"
  type        = string
  default     = "realtime-voting"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}