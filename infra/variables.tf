# Input variables for the module

variable "location" {
  description = "The supported Azure location where the resource deployed"
  type        = string
}

variable "environment_name" {
  description = "The name of the azd environment to be deployed"
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "ai_locations" {
  description = "List of locations for AI Foundry instances"
  type        = list(string)
}

variable "openai_chat" {
  description = "OpenAI Chat model configuration"
  type = object({
    model_name    = string
    model_version = string
    deploy_type   = string
    capacity      = number
  })
}

variable "openai_embedding" {
  description = "OpenAI Embedding model configuration"
  type = object({
    model_name    = string
    model_version = string
    deploy_type   = string
    capacity      = number
  })
}


variable "tpm_limit_token" {
  description = "Tokens per minute limit for OpenAI"
  type        = number
  default     = 30000
}

variable "knowledge_reasoning_effort" {
  description = "Retrieval reasoning effort for Knowledge Base. Valid values: minimal, low, medium"
  type        = string
  default     = "medium"
  validation {
    condition     = contains(["minimal", "low", "medium"], var.knowledge_reasoning_effort)
    error_message = "Allowed values for knowledge_reasoning_effort are: minimal, low, medium"
  }
}


