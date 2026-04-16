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

variable "ais_mi_client_id" {
  description = "AI Services Managed Identity Client ID for APIM named value"
  type        = string
}

variable "api_management_logger_id" {
  type = string
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
