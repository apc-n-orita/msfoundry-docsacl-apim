terraform {
  required_providers {
    azurerm = {
      version = "~>4.42.0"
      source  = "hashicorp/azurerm"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~>2.0.0"
    }
  }
}


resource "azurerm_api_management_api" "aisearch" {
  name                  = "aisearch"
  resource_group_name   = var.resource_group_name
  api_management_name   = var.api_management_name
  revision              = "1"
  display_name          = "aisearch-api"
  path                  = "aisearch"
  description           = "Azure Cognitive Search API"
  protocols             = ["https"]
  subscription_required = false

  subscription_key_parameter_names {
    header = "api-key"
    query  = "subscription-key"
  }

  import {
    content_format = "openapi"
    content_value = templatefile("${path.module}/files/api/aisearch_openapi.yaml",
      {
        apim_gateway_url = var.apim_gateway_url != null ? var.apim_gateway_url : ""
      }
    )
  }
}

resource "azapi_resource" "aisearch_backend" {
  type                      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name                      = "aisearch"
  parent_id                 = var.api_management_id
  schema_validation_enabled = false

  body = {
    properties = {
      protocol = "http"
      url      = "https://${var.aisearch_name}.search.windows.net/"
      credentials = {
        managedIdentity = {
          resource = "https://search.azure.com/"
        }
      }
      circuitBreaker = {
        rules = [
          {
            name             = "AIBreakerRule"
            acceptRetryAfter = true
            tripDuration     = "PT1M"
            failureCondition = {
              count    = 3
              interval = "PT5M"
              statusCodeRanges = [
                {
                  min = 429
                  max = 429
                },
                {
                  min = 500
                  max = 599
                }
              ]
            }
          }
        ]
      }
    }
  }
}


resource "azurerm_api_management_named_value" "aisearch_backend_pool" {
  name                = "aisBackendPool"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "aisBackendPool"
  value               = azapi_resource.aisearch_backend.name
  secret              = false
}

resource "azurerm_api_management_api_policy" "aisearch" {
  api_name            = azurerm_api_management_api.aisearch.name
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  xml_content = templatefile("${path.module}/files/policy/aisearch_api_v2.xml", {
    aisBackendPool = azurerm_api_management_named_value.aisearch_backend_pool.name
  })
}

resource "azurerm_api_management_api_diagnostic" "aisearch" {
  identifier                = "applicationinsights"
  api_name                  = azurerm_api_management_api.aisearch.name
  api_management_name       = var.api_management_name
  resource_group_name       = var.resource_group_name
  api_management_logger_id  = var.api_management_logger_id
  sampling_percentage       = 100.0
  always_log_errors         = true
  log_client_ip             = true
  verbosity                 = "information"
  http_correlation_protocol = "W3C"

  frontend_request {
    body_bytes = 0
  }

  frontend_response {
    body_bytes = 0
  }

  backend_request {
    body_bytes = 0
  }

  backend_response {
    body_bytes = 0
  }
}

resource "azurerm_role_assignment" "aisearch" {
  scope                = var.aisearch_id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = var.apim_principal_id
}
