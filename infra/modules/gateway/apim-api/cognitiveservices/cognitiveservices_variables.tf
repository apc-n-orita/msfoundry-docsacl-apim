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

variable "api_management_logger_id" {
  type = string
}

variable "api_management_id" {
  type = string
}

variable "apim_gateway_url" {
  type = string
}
