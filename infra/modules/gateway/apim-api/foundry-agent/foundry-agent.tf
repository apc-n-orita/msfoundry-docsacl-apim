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


resource "azurerm_api_management_api" "foundryagent" {
  name                  = "foundryagent"
  resource_group_name   = var.resource_group_name
  api_management_name   = var.api_management_name
  revision              = "1"
  display_name          = "FoundryAgent"
  path                  = "foundryagent"
  description           = "Azure FoundryAgent API"
  protocols             = ["https"]
  subscription_required = false

  subscription_key_parameter_names {
    header = "api-key"
    query  = "subscription-key"
  }

  import {
    content_format = "openapi"
    content_value = templatefile("${path.module}/files/api/foundryagent_openapi.yaml",
      {
        apim_gateway_url = var.apim_gateway_url
      }
    )
  }
}

resource "azapi_resource" "foundry_backend" {
  for_each = {
    for idx, name in var.foundry_backend_names :
    idx => name
  }

  type                      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name                      = each.value
  parent_id                 = var.api_management_id
  schema_validation_enabled = false

  body = {
    properties = {
      protocol = "http"
      url      = "https://${each.value}.services.ai.azure.com/"
      tls = {
        validateCertificateChain = false
        validateCertificateName  = false
      }
      credentials = {
        managedIdentity = {
          resource = "https://ai.azure.com/"
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

resource "azapi_resource" "backend_pool" {
  type                      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name                      = "aifbackendpool"
  parent_id                 = var.api_management_id
  schema_validation_enabled = false # body.property配下のprotocol/url の検証を無効化
  body = {
    properties = {
      type = "Pool"
      pool = {
        services = [for k, v in azapi_resource.foundry_backend : {
          id = v.id
        }]
        sessionAffinity = {
          sessionId = {
            name   = "SessionId"
            source = "cookie"
          }
        }
      }
    }
  }
}

# --- Named Values ---
resource "azurerm_api_management_named_value" "entra_id_tenant_id" {
  name                = "EntraIDTenantId"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "EntraIDTenantId"
  value               = var.entra_app_tenant_id
  secret              = true
}

resource "azurerm_api_management_named_value" "entra_id_group" {
  name                = "EntraIDGroup"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "EntraIDGroup"
  value               = var.entra_app_group_id
  secret              = true
}

resource "azurerm_api_management_named_value" "aif_backend_pool" {
  name                = "AIFBackendPool"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = "AIFBackendPool"
  value               = azapi_resource.backend_pool.name
  secret              = false
}

resource "azurerm_api_management_api_policy" "foundryagent" {
  api_name            = azurerm_api_management_api.foundryagent.name
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  xml_content = templatefile("${path.module}/files/policy/foundryagent_api_v2.xml", {
    AIFBackendPool = azurerm_api_management_named_value.aif_backend_pool.name
  })

}


resource "azurerm_api_management_api_diagnostic" "foundryagent" {
  identifier                = "applicationinsights"
  api_name                  = azurerm_api_management_api.foundryagent.name
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


resource "azapi_resource" "apim_foundryagent_api_diagnostic_monitor" {
  type                      = "Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01"
  name                      = "azuremonitor"
  parent_id                 = azurerm_api_management_api.foundryagent.id
  schema_validation_enabled = false
  body = {
    properties = {
      alwaysLog   = "allErrors"
      logClientIp = true
      verbosity   = "information"
      loggerId    = "${var.api_management_id}/loggers/azuremonitor"

      sampling = {
        percentage   = 100.0
        samplingType = "fixed"
      }

      frontend = {
        request = {
          body = {
            bytes    = 0
            sampling = null
          }
          headers = []
        }
        response = {
          body = {
            bytes    = 0
            sampling = null
          }
          headers = []
        }
      }

      backend = {
        request = {
          body = {
            bytes    = 0
            sampling = null
          }
          headers = []
        }
        response = {
          body = {
            bytes    = 0
            sampling = null
          }
          headers = []
        }
      }

      largeLanguageModel = {
        logs = "enabled"
        requests = {
          maxSizeInBytes = 32768
          messages       = "all"
        }
        responses = {
          maxSizeInBytes = 32768
          messages       = "all"
        }
      }
    }
  }
}

resource "azurerm_role_assignment" "foundryagent" {
  for_each = {
    for idx, id in var.foundry_backend_ids :
    idx => id
  }

  scope                = each.value
  role_definition_name = "Cognitive Services User"
  principal_id         = var.apim_principal_id
}

resource "azurerm_api_management_product" "foundryagent" {
  product_id            = "foundryagent"
  api_management_name   = var.api_management_name
  resource_group_name   = var.resource_group_name
  description           = "API Product for FoundryAgent"
  display_name          = "FoundryAgent API Product"
  subscription_required = false
  approval_required     = false
  published             = true
}
resource "azurerm_api_management_product_api" "foundryagent" {
  api_name            = azurerm_api_management_api.foundryagent.name
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name
  product_id          = azurerm_api_management_product.foundryagent.product_id
}

resource "azurerm_api_management_product_policy" "foundryagent" {
  product_id          = azurerm_api_management_product.foundryagent.product_id
  api_management_name = var.api_management_name
  resource_group_name = var.resource_group_name

  xml_content = templatefile("${path.module}/files/policy/foundryagent_product_v2.xml", {
    modeldeploymentname = var.ai_model_deploymentname
    tokenlimit          = var.tpm_limit_token
    EntraIDGroup        = azurerm_api_management_named_value.entra_id_group.name
    EntraIDTenantId     = azurerm_api_management_named_value.entra_id_tenant_id.name
  })
}
