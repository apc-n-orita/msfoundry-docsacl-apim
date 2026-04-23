locals {
  tags           = { azd-env-name : var.environment_name }
  sha            = base64encode(sha256("${var.environment_name}${var.location}${var.subscription_id}"))
  resource_token = substr(replace(lower(local.sha), "[^A-Za-z0-9_]", ""), 0, 13)
  apim = {
    sku             = "BasicV2"
    skuCount        = 1
    publisher_email = "testuser@example.com"
    publisher_name  = "testuser"
  }
  network_access = {
    default_action = "Allow"
    public_access  = "Enabled"
  }
  docs = {
    docs_files = [for f in fileset("./docs", "*") : f if f != "dummy.txt"]
    acl_types  = ["noacl", "acl"]
  }
  agent_payload = jsonencode({
    name        = "info-agent-tartaria"
    version     = "1"
    description = ""
    definition = {
      kind         = "prompt"
      model        = var.openai_chat.model_name
      instructions = "- すべての情報はツールまたはナレッジから取得してください。\n- 都市伝説的要素を含む場合でも、AI 独自の見解や評価は加えず、取得情報の提示のみに徹してください。\n     - 都市伝説的要素を含む回答の末尾には、最終的な判断をユーザーに委ねる旨の一文を必ず追記してください。（都市伝説的要素以外の場合は不要）\n- 必ず参照情報も併せて提示してください。"
      tools = [
        {
          type                  = "mcp"
          server_label          = azapi_resource.conn_foundryiq["0"].name
          server_url            = azapi_resource.conn_foundryiq["0"].body.properties.target
          allowed_tools         = { tool_names = ["knowledge_base_retrieve"] }
          require_approval      = "never"
          project_connection_id = azapi_resource.conn_foundryiq["0"].name
        }
      ]
    }
    status = "active"
  })
}

resource "azurecaf_name" "rg_name" {
  name          = "${var.environment_name}-${substr(local.resource_token, 0, 3)}"
  resource_type = "azurerm_resource_group"
  random_length = 0
  clean_input   = true
}


resource "azurecaf_name" "appinsights_name" {
  name          = "${var.environment_name}-${substr(local.resource_token, 0, 3)}"
  resource_type = "azurerm_application_insights"
  random_length = 0
  clean_input   = true
}

resource "azurecaf_name" "law_name" {
  name          = "${var.environment_name}-${substr(local.resource_token, 0, 3)}"
  resource_type = "azurerm_log_analytics_workspace"
  random_length = 0
  clean_input   = true
}

resource "azurecaf_name" "apim_name" {
  name          = "${var.environment_name}-${substr(local.resource_token, 0, 3)}"
  resource_type = "azurerm_api_management"
  random_length = 0
  clean_input   = true
}

resource "azurecaf_name" "storage_name" {
  name          = "${var.environment_name}${substr(local.resource_token, 0, 3)}"
  resource_type = "azurerm_storage_account"
  random_length = 0
  clean_input   = true
}

# Deploy resource group
resource "azurerm_resource_group" "rg" {
  name     = azurecaf_name.rg_name.result
  location = var.location
  // Tag the resource group with the azd environment name
  // This should also be applied to all resources created in this module
  tags = { azd-env-name : var.environment_name }
}

resource "azurerm_application_insights" "AI" {
  name                          = azurecaf_name.appinsights_name.result
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  application_type              = "web"
  workspace_id                  = azurerm_log_analytics_workspace.law.id
  local_authentication_disabled = false
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = azurecaf_name.law_name.result
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

module "ai_foundry" {
  for_each                   = { for idx, s in var.ai_locations : idx => s }
  source                     = "./modules/AI/AIservice"
  name                       = "aif-${var.environment_name}-${format("%03d", each.key + 1)}"
  location                   = each.value
  resource_group_name        = azurerm_resource_group.rg.name
  tags                       = local.tags
  disableLocalauth           = true
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  network_acls = {
    default_action = local.network_access.default_action
  }
  public_network_access = local.network_access.public_access
  ai_model = [
    {
      model                  = var.openai_chat.model_name
      version                = var.openai_chat.model_version
      format                 = "OpenAI"
      deploytype             = var.openai_chat.deploy_type
      capacity               = var.openai_chat.capacity
      rai_policy_name        = "Microsoft.DefaultV2"
      version_upgrade_option = "OnceNewDefaultVersionAvailable"
    },
    {
      model                      = var.openai_embedding.model_name
      version                    = var.openai_embedding.model_version
      format                     = "OpenAI"
      deploytype                 = var.openai_embedding.deploy_type
      capacity                   = var.openai_embedding.capacity
      rai_policy_name            = "Microsoft.DefaultV2"
      dynamic_throttling_enabled = true
    }
  ]
}

module "ai_search" {
  source                        = "./modules/AI/AIsearch"
  public_network_access_enabled = local.network_access.public_access == "Enabled" ? true : false
  rg_name                       = azurerm_resource_group.rg.name
  location                      = var.location
  name                          = "ais-${var.environment_name}-${substr(local.resource_token, 0, 3)}"
  local_authentication_enabled  = false
  tags                          = local.tags
  log_analytics_workspace_id    = azurerm_log_analytics_workspace.law.id
  search_service_sku            = "standard" #サンプルpdfが16mbを超えるため、Standardを使用。インデクシング後、ポータルからBasicにダウングレード可能。(terraformの場合、再作成になるため、注意。)
  #search_service_sku  = "basic"
  semantic_search_sku = "free"
}

module "storage" {
  source                          = "./modules/storage"
  name                            = lower("${azurecaf_name.storage_name.result}")
  location                        = var.location
  resource_group_name             = azurerm_resource_group.rg.name
  tags                            = local.tags
  shared_access_key_enabled       = false
  tier                            = "Standard"
  replication_type                = "LRS"
  log_analytics_workspace_id      = azurerm_log_analytics_workspace.law.id
  public_network_access           = local.network_access.public_access
  is_hns_enabled                  = true
  allow_nested_items_to_be_public = false
  blob_delete_retention_days      = 7
  network_acls = {
    default_action = "${local.network_access.default_action}"
  }
}

module "apim" {
  source = "./modules/gateway/apim"

  location                   = var.location
  rg_name                    = azurerm_resource_group.rg.name
  tags                       = local.tags
  sku                        = local.apim.sku
  skuCount                   = local.apim.skuCount
  name                       = azurecaf_name.apim_name.result
  publisher_email            = local.apim.publisher_email
  publisher_name             = local.apim.publisher_name
  application_insights_name  = azurerm_application_insights.AI.name
  identity_type              = "SystemAssigned"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
}


module "apim_api_foundry_agent" {
  source = "./modules/gateway/apim-api/foundry-agent"

  resource_group_name      = azurerm_resource_group.rg.name
  api_management_name      = module.apim.APIM_SERVICE_NAME
  foundry_backend_names    = [for k, v in module.ai_foundry : v.name]
  foundry_backend_ids      = [for k, v in module.ai_foundry : v.ai_foundry_id]
  entra_app_tenant_id      = data.azurerm_client_config.current.tenant_id
  entra_app_group_id       = azuread_group.adls_acl_group.object_id
  ai_model_deploymentname  = var.openai_chat.model_name
  tpm_limit_token          = var.tpm_limit_token
  api_management_logger_id = module.apim.API_MANAGEMENT_LOGGER_ID
  api_management_id        = module.apim.APIM_SERVICE_ID
  apim_gateway_url         = module.apim.gateway_url
  apim_principal_id        = module.apim.APIM_MANAGED_IDENTITY_PRINCIPAL_ID
}

# AI SearchのマネージドIDからアプリケーションID(client_id)を取得
data "azuread_service_principal" "ai_search" {
  object_id = module.ai_search.search_service_identity_principal_id
}

module "apim_api_openai" {
  source = "./modules/gateway/apim-api/openai"

  resource_group_name      = azurerm_resource_group.rg.name
  api_management_name      = module.apim.APIM_SERVICE_NAME
  foundry_backend_names    = [for k, v in module.ai_foundry : v.name]
  foundry_backend_ids      = [for k, v in module.ai_foundry : v.ai_foundry_id]
  ais_mi_client_id         = data.azuread_service_principal.ai_search.client_id
  api_management_logger_id = module.apim.API_MANAGEMENT_LOGGER_ID
  api_management_id        = module.apim.APIM_SERVICE_ID
  apim_gateway_url         = module.apim.gateway_url
  apim_principal_id        = module.apim.APIM_MANAGED_IDENTITY_PRINCIPAL_ID
  depends_on               = [module.apim_api_foundry_agent]
}

module "apim_api_cognitiveservices" {
  source = "./modules/gateway/apim-api/cognitiveservices"

  resource_group_name      = azurerm_resource_group.rg.name
  api_management_name      = module.apim.APIM_SERVICE_NAME
  foundry_backend_names    = [for k, v in module.ai_foundry : v.name]
  foundry_backend_ids      = [for k, v in module.ai_foundry : v.ai_foundry_id]
  api_management_logger_id = module.apim.API_MANAGEMENT_LOGGER_ID
  api_management_id        = module.apim.APIM_SERVICE_ID
  apim_gateway_url         = module.apim.gateway_url
  depends_on               = [module.apim_api_foundry_agent]
}


# Easy Auth (App Service Authentication) settings
resource "random_uuid" "user_impersonation_scope_id" {}

resource "azuread_application" "oauth_app" {
  display_name = "oauth-app-${substr(local.resource_token, 0, 3)}"
  owners       = [data.azurerm_client_config.current.object_id]

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }


  }
  required_resource_access {
    resource_app_id = "880da380-985e-4198-81b9-e05b1cc53158" # AI Search
    resource_access {
      id   = "a4165a31-5d9e-4120-bd1e-9d88c66fd3b8" # User.Impersonation
      type = "Scope"
    }


  }

  lifecycle {
    ignore_changes = [
      identifier_uris,
      api,
    ]
  }
}


# Set Application ID URI
resource "azuread_application_identifier_uri" "entra_app_uri" {
  application_id = azuread_application.oauth_app.id
  identifier_uri = "api://${azuread_application.oauth_app.client_id}"
}

# Set user_impersonation scope
resource "azuread_application_permission_scope" "user_impersonation" {
  application_id = azuread_application.oauth_app.id
  scope_id       = random_uuid.user_impersonation_scope_id.result
  value          = "user_impersonation"

  admin_consent_description  = "Allow the application to access AIagent App on behalf of the signed-in user."
  admin_consent_display_name = "Access AIagent App"
  user_consent_description   = "Allow the application to access AIagent App on your behalf."
  user_consent_display_name  = "Access AIagent App"
  type                       = "User" # Both admin and user can consent
}


resource "azuread_application_pre_authorized" "oauth_app" {
  application_id       = azuread_application.oauth_app.id
  authorized_client_id = "04b07795-8ddb-461a-bbee-02f9e1bf7b46" # Azure CLI

  permission_ids = [
    azuread_application_permission_scope.user_impersonation.scope_id,
  ]
}


resource "azuread_group" "adls_acl_group" {
  display_name     = "adls-acl-group-${substr(local.resource_token, 0, 3)}"
  security_enabled = true
  members          = [data.azurerm_client_config.current.object_id]
}


resource "azurerm_storage_data_lake_gen2_filesystem" "ais_docs" {
  depends_on         = [azurerm_role_assignment.current_user_storage_blob_data_contributor]
  storage_account_id = module.storage.storage_account_id
  name               = "ais-docs"
  ace {
    type        = "user"
    permissions = "rwx"
  }
  ace {
    type        = "group"
    permissions = "r-x"
  }
  ace {
    type        = "group"
    id          = azuread_group.adls_acl_group.object_id
    permissions = "--x"
  }
  ace {
    type        = "mask"
    permissions = "r-x"
  }
  ace {
    type        = "other"
    permissions = "---"
  }
}

# Tartarian/ ディレクトリのACL設定

resource "azurerm_storage_data_lake_gen2_path" "tartarian" {
  depends_on         = [azurerm_role_assignment.current_user_storage_blob_data_contributor]
  storage_account_id = module.storage.storage_account_id
  filesystem_name    = azurerm_storage_data_lake_gen2_filesystem.ais_docs.name
  path               = "Tartarian"
  resource           = "directory"

  ace {
    type        = "user"
    permissions = "rwx"
  }
  ace {
    type        = "group"
    permissions = "r-x"
  }
  ace {
    type        = "group"
    id          = azuread_group.adls_acl_group.object_id
    permissions = "r-x"
  }
  ace {
    type        = "mask"
    permissions = "r-x"
  }
  ace {
    type        = "other"
    permissions = "---"
  }
  ace {
    scope       = "default"
    type        = "user"
    permissions = "rwx"
  }
  ace {
    scope       = "default"
    type        = "group"
    permissions = "r-x"
  }
  ace {
    scope       = "default"
    type        = "group"
    id          = azuread_group.adls_acl_group.object_id
    permissions = "r-x"
  }
  ace {
    scope       = "default"
    type        = "mask"
    permissions = "r-x"
  }
  ace {
    scope       = "default"
    type        = "other"
    permissions = "---"
  }
}

resource "azurerm_storage_blob" "docs" {
  for_each               = { for idx, file in local.docs.docs_files : idx => file }
  name                   = "${azurerm_storage_data_lake_gen2_path.tartarian.path}/${each.value}"
  storage_account_name   = module.storage.name
  storage_container_name = azurerm_storage_data_lake_gen2_filesystem.ais_docs.name
  type                   = "Block"
  source                 = "./docs/${each.value}"
  access_tier            = "Hot"
  content_type           = endswith(each.value, ".pdf") ? "application/pdf" : "application/octet-stream"
  content_md5            = filemd5("./docs/${each.value}")
  depends_on             = [azurerm_storage_data_lake_gen2_path.tartarian, ]
}

resource "azapi_resource" "ai_foundry_project" {
  for_each                  = module.ai_foundry
  type                      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name                      = "aiproject"
  parent_id                 = each.value.ai_foundry_id
  location                  = each.value.location
  schema_validation_enabled = false
  body = {
    sku = {
      name = "S0"
    }
    identity = {
      type = "SystemAssigned"
    }
    properties = {
      displayName = "aiproject"
      description = "A project for the AI Foundry account"
    }
  }
  response_export_values = [
    "identity.principalId",
    "properties.internalId"
  ]
}

## Wait 10 seconds for the AI Foundry project system-assigned managed identity to be created and to replicate
## through Entra ID
resource "time_sleep" "wait_project_identities" {
  for_each = azapi_resource.ai_foundry_project
  depends_on = [
    azapi_resource.ai_foundry_project
  ]
  create_duration = "10s"
}

# AI Foundry project connections
resource "azapi_resource" "conn_appi" {
  for_each                  = azapi_resource.ai_foundry_project
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = "appi-connection"
  parent_id                 = each.value.id
  schema_validation_enabled = false

  body = {
    properties = {
      category      = "AppInsights"
      target        = azurerm_application_insights.AI.id
      authType      = "ApiKey"
      isSharedToAll = false
      group         = "ServicesAndApps"
      isDefault     = true
      peRequirement = "NotRequired"
      peStatus      = "NotApplicable"
      credentials = {
        key = azurerm_application_insights.AI.connection_string
      }
      useWorkspaceManagedIdentity = false
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_application_insights.AI.id
      }
    }
  }
}

resource "azapi_resource" "conn_aisearch" {
  for_each                  = azapi_resource.ai_foundry_project
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name                      = "aisearch-connection"
  parent_id                 = each.value.id
  schema_validation_enabled = false
  body = {
    name = "aisearch-connection"
    properties = {
      category = "CognitiveSearch"
      target   = "https://${module.ai_search.search_service_name}.search.windows.net"
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ApiVersion = "2025-05-01-preview"
        ResourceId = module.ai_search.search_service_id
        location   = var.location
      }
    }
  }
}


resource "azapi_resource" "conn_foundryiq" {
  for_each                  = azapi_resource.ai_foundry_project
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = "foundryIQ"
  parent_id                 = each.value.id
  schema_validation_enabled = false

  body = {
    properties = {
      audience      = "https://search.azure.com"
      authType      = "ProjectManagedIdentity"
      category      = "RemoteTool"
      group         = "GenericProtocol"
      isDefault     = true
      isSharedToAll = false
      peRequirement = "NotRequired"
      peStatus      = "NotApplicable"
      metadata = {
        type = "custom_MCP"
      }
      target                      = "https://${module.ai_search.search_service_name}.search.windows.net/knowledgebases/kb-tartalia-${local.docs.acl_types[0]}-gen2/mcp?api-version=2025-11-01-Preview"
      useWorkspaceManagedIdentity = false
    }
  }


}

resource "azapi_resource" "conn_foundryiq_docsacl" {
  for_each                  = azapi_resource.ai_foundry_project
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = "foundryIQ-docsacl"
  parent_id                 = each.value.id
  schema_validation_enabled = false

  body = {
    properties = {
      audience      = "https://search.azure.com"
      authType      = "ProjectManagedIdentity"
      category      = "RemoteTool"
      group         = "GenericProtocol"
      isDefault     = false
      isSharedToAll = false
      peRequirement = "NotRequired"
      peStatus      = "NotApplicable"
      metadata = {
        type = "custom_MCP"
      }
      target                      = "https://${module.ai_search.search_service_name}.search.windows.net/knowledgebases/kb-tartalia-${local.docs.acl_types[1]}-gen2/mcp?api-version=2025-11-01-Preview"
      useWorkspaceManagedIdentity = false
    }
  }
}


# ロール割り当て
resource "azurerm_role_assignment" "ai_foundry_project_azure_ai_user" {
  for_each             = azapi_resource.ai_foundry_project
  scope                = each.value.id
  role_definition_name = "Azure AI User"
  principal_id         = each.value.output.identity.principalId
  depends_on           = [time_sleep.wait_project_identities]
}

resource "azurerm_role_assignment" "ai_foundry_project_ai_search_index_data_reader" {
  for_each             = azapi_resource.ai_foundry_project
  depends_on           = [time_sleep.wait_project_identities]
  scope                = module.ai_search.search_service_id
  role_definition_name = "Search Index Data Reader"
  principal_id         = each.value.output.identity.principalId
}

resource "azurerm_role_assignment" "ai_foundry_project_monitoring_metrics_publisher" {
  for_each             = azapi_resource.ai_foundry_project
  depends_on           = [time_sleep.wait_project_identities]
  scope                = azurerm_application_insights.AI.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = each.value.output.identity.principalId
}

resource "azurerm_role_assignment" "aisearch_storage_blob_reader" {
  scope                = module.storage.storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = module.ai_search.search_service_identity_principal_id
}

resource "azurerm_role_assignment" "current_user_search_service_contributor" {
  scope                = module.ai_search.search_service_id
  role_definition_name = "Search Service Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "current_user_search_index_data_contributor" {
  scope                = module.ai_search.search_service_id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "current_user_search_index_data_reader" {
  scope                = module.ai_search.search_service_id
  role_definition_name = "Search Index Data Reader"
  principal_id         = data.azurerm_client_config.current.object_id
}
resource "azurerm_role_assignment" "current_user_storage_blob_data_contributor" {
  scope                = module.storage.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "current_user_metrics_publisher" {
  scope                = azurerm_application_insights.AI.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = data.azurerm_client_config.current.object_id
}


resource "null_resource" "provision_search_index" {
  for_each = toset(local.docs.acl_types)
  triggers = {
    subscription_id      = var.subscription_id
    resource_group_name  = azurerm_resource_group.rg.name
    search_service_name  = module.ai_search.search_service_name
    datasource_name      = "ds-${each.key}-gen2"
    storage_account_name = module.storage.name
    blob_container_name  = azurerm_storage_data_lake_gen2_filesystem.ais_docs.name
    blob_query           = "Tartarian/"
    index_name           = "index-${each.key}-gen2"
    skillset_name        = "skill-${each.key}-gen2"
    indexer_name         = "indexer-${each.key}-gen2"
    resource_uri         = module.apim.gateway_url
    deployment_id        = var.openai_embedding.model_name
    model_name           = var.openai_embedding.model_name
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      bash ${path.module}/scripts/ais_set_${each.key}_index.sh \
        ${self.triggers.subscription_id} \
        ${self.triggers.resource_group_name} \
        ${self.triggers.search_service_name} \
        ${self.triggers.datasource_name} \
        ${self.triggers.storage_account_name} \
        ${self.triggers.blob_container_name} \
        ${self.triggers.blob_query} \
        ${self.triggers.index_name} \
        ${self.triggers.skillset_name} \
        ${self.triggers.indexer_name} \
        ${self.triggers.resource_uri} \
        ${self.triggers.deployment_id} \
        ${self.triggers.model_name}
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      bash ${path.module}/scripts/ais_delete_index.sh \
        ${self.triggers.search_service_name} \
        ${self.triggers.indexer_name} \
        ${self.triggers.skillset_name} \
        ${self.triggers.index_name} \
        ${self.triggers.datasource_name}
    EOT
  }

  depends_on = [module.apim_api_openai, module.ai_foundry, azurerm_storage_blob.docs,
  ]
}


resource "null_resource" "provision_search_knowledge_acl" {
  for_each = null_resource.provision_search_index
  triggers = {
    search_service_name   = module.ai_search.search_service_name
    knowledge_source_name = "ks-tartalia-${each.key}-gen2"
    index_name            = "index-${each.key}-gen2"
    knowledge_base_name   = "kb-tartalia-${each.key}-gen2"
    resource_uri          = module.apim.gateway_url
    chat_deployment_id    = var.openai_chat.model_name
    chat_model_name       = var.openai_chat.model_name
    reasoning_effort      = var.knowledge_reasoning_effort
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      bash ${path.module}/scripts/ais_set_knowledge.sh \
        ${self.triggers.search_service_name} \
        ${self.triggers.knowledge_source_name} \
        ${self.triggers.index_name} \
        ${self.triggers.knowledge_base_name} \
        ${self.triggers.resource_uri} \
        ${self.triggers.chat_deployment_id} \
        ${self.triggers.chat_model_name} \
        ${self.triggers.reasoning_effort}
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      bash ${path.module}/scripts/ais_delete_knowledge.sh \
        ${self.triggers.search_service_name} \
        ${self.triggers.knowledge_base_name} \
        ${self.triggers.knowledge_source_name}
    EOT
  }
}

resource "null_resource" "foundry_agent" {
  for_each = azapi_resource.ai_foundry_project
  triggers = {
    endpoint     = "https://${module.ai_foundry[each.key].name}.services.ai.azure.com/api/projects/${each.value.name}"
    project_name = each.value.name
  }

  provisioner "local-exec" {
    command     = <<EOT
      ENDPOINT="${self.triggers.endpoint}"
      ACCESS_TOKEN="$(az account get-access-token --resource https://ai.azure.com/ --query accessToken -o tsv)"
      curl -X POST "$ENDPOINT/agents?api-version=v1" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -d '${local.agent_payload}'
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "azapi_resource" "grafana_dashboard" {
  type                      = "Microsoft.Dashboard/dashboards@2025-09-01-preview"
  name                      = "AI-dashboard-${substr(local.resource_token, 0, 3)}"
  location                  = azurerm_resource_group.rg.location
  parent_id                 = azurerm_resource_group.rg.id
  schema_validation_enabled = false
  tags = {
    GrafanaDashboardTags         = "agent-framework"
    AzMonGrafanaDashboardId      = "AgentFramework###ver###4"
    GrafanaDashboardResourceType = "microsoft.insights/components"
  }
  body = {
    properties = {}
  }
}

resource "azapi_resource" "grafana_dashboard_definition" {
  type                      = "Microsoft.Dashboard/dashboards/dashboardDefinitions@2025-09-01-preview"
  name                      = "default"
  parent_id                 = azapi_resource.grafana_dashboard.id
  schema_validation_enabled = false
  body = {
    properties = {
      serializedData = templatefile("./grafanadashb/grafana-dash.tftpl", {
        subscription_id     = var.subscription_id
        resource_group_name = azurerm_resource_group.rg.name
        appinsights_name    = azurerm_application_insights.AI.name
        dashboard_name      = "AI-dashboard-${substr(local.resource_token, 0, 3)}"
      })
    }
  }
}
