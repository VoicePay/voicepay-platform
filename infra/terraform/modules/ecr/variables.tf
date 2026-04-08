variable "repository_names" {
  description = "List of ECR repository names to create (without the voicepay- prefix)"
  type        = list(string)
  default     = ["auth", "payment", "notification"]
}

variable "image_retention_count" {
  description = "Number of images to retain per repository"
  type        = number
  default     = 3
}

variable "image_tag_mutability" {
  description = "Image tag mutability setting. Use IMMUTABLE in prod to prevent tag overwriting."
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
