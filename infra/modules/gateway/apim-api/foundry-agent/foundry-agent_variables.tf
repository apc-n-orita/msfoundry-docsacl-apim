variable "resource_group_name" {}
variable "api_management_name" {}

variable "foundry_backend_names" {
  description = "List of Foundry backend names (e.g. ['aif-env-001', 'aif-env-002'])"
  type        = list(string)
}

variable "foundry_backend_ids" {
  description = "Set of Foundry backend resource IDs for role assignment scope"
  type        = list(string)
}

variable "entra_app_tenant_id" {
  description = "Entra ID tenant ID for API policy"
  type        = string
}

variable "entra_app_group_id" {
  description = "Entra ID group ID for API policy"
  type        = string
}

variable "ai_model_deploymentname" {
  description = "AI model deployment name"
  type        = string
}

variable "api_management_logger_id" {
  type = string
}

variable "tpm_limit_token" {
  description = "Tokens per minute limit"
  type        = number
  default     = 30000
}

variable "api_management_id" {
  description = "API Management resource ID (for backend parent_id)"
  type        = string
}

variable "apim_gateway_url" {
  description = "API Management Gateway URL (for OpenAPI template)"
  type        = string
}

variable "apim_principal_id" {
  description = "Principal ID for role assignment (APIM managed identity)"
  type        = string
}
