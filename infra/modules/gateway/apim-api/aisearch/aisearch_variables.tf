variable "resource_group_name" {}
variable "api_management_name" {}

variable "api_management_logger_id" {
  type = string
}

variable "api_management_id" {
  type = string
}

variable "apim_gateway_url" {
  type = string
}

variable "apim_principal_id" {
  type = string
}

variable "aisearch_id" {
  type = string
}

variable "aisearch_name" {
  type = string

}

variable "diagnostic_sampling_percentage" {
  description = "APIM診断のサンプリング率（0.0 〜 100.0）。本番環境では 20.0 〜 50.0 を推奨。"
  type        = number
  default     = 100.0
  validation {
    condition     = var.diagnostic_sampling_percentage >= 0.0 && var.diagnostic_sampling_percentage <= 100.0
    error_message = "diagnostic_sampling_percentage must be between 0.0 and 100.0"
  }
}
