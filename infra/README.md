<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.1.7, < 2.0.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | ~>2.0.0 |
| <a name="requirement_azuread"></a> [azuread](#requirement\_azuread) | ~>3.5.0 |
| <a name="requirement_azurecaf"></a> [azurecaf](#requirement\_azurecaf) | ~>1.2.24 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~>4.42.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~>3.2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | 2.0.1 |
| <a name="provider_azuread"></a> [azuread](#provider\_azuread) | 3.5.0 |
| <a name="provider_azurecaf"></a> [azurecaf](#provider\_azurecaf) | 1.2.32 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.42.0 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.2.4 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.8.1 |
| <a name="provider_time"></a> [time](#provider\_time) | 0.13.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_ai_foundry"></a> [ai\_foundry](#module\_ai\_foundry) | ./modules/AI/AIservice | n/a |
| <a name="module_ai_search"></a> [ai\_search](#module\_ai\_search) | ./modules/AI/AIsearch | n/a |
| <a name="module_apim"></a> [apim](#module\_apim) | ./modules/gateway/apim | n/a |
| <a name="module_apim_api_cognitiveservices"></a> [apim\_api\_cognitiveservices](#module\_apim\_api\_cognitiveservices) | ./modules/gateway/apim-api/cognitiveservices | n/a |
| <a name="module_apim_api_foundry_agent"></a> [apim\_api\_foundry\_agent](#module\_apim\_api\_foundry\_agent) | ./modules/gateway/apim-api/foundry-agent | n/a |
| <a name="module_apim_api_openai"></a> [apim\_api\_openai](#module\_apim\_api\_openai) | ./modules/gateway/apim-api/openai | n/a |
| <a name="module_storage"></a> [storage](#module\_storage) | ./modules/storage | n/a |

## Resources

| Name | Type |
|------|------|
| [azapi_resource.ai_foundry_project](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.conn_aisearch](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.conn_appi](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.conn_foundryiq](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.conn_foundryiq_docsacl](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azuread_application.oauth_app](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application) | resource |
| [azuread_application_identifier_uri.entra_app_uri](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_identifier_uri) | resource |
| [azuread_application_permission_scope.user_impersonation](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_permission_scope) | resource |
| [azuread_application_pre_authorized.oauth_app](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application_pre_authorized) | resource |
| [azuread_group.adls_acl_group](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/group) | resource |
| [azurecaf_name.apim_name](https://registry.terraform.io/providers/aztfmod/azurecaf/latest/docs/resources/name) | resource |
| [azurecaf_name.appinsights_name](https://registry.terraform.io/providers/aztfmod/azurecaf/latest/docs/resources/name) | resource |
| [azurecaf_name.law_name](https://registry.terraform.io/providers/aztfmod/azurecaf/latest/docs/resources/name) | resource |
| [azurecaf_name.rg_name](https://registry.terraform.io/providers/aztfmod/azurecaf/latest/docs/resources/name) | resource |
| [azurecaf_name.storage_name](https://registry.terraform.io/providers/aztfmod/azurecaf/latest/docs/resources/name) | resource |
| [azurerm_application_insights.AI](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_insights) | resource |
| [azurerm_log_analytics_workspace.law](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace) | resource |
| [azurerm_resource_group.rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_role_assignment.ai_foundry_project_ai_search_index_data_reader](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.ai_foundry_project_azure_ai_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.ai_foundry_project_monitoring_metrics_publisher](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.aisearch_storage_blob_reader](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.current_user_metrics_publisher](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.current_user_search_index_data_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.current_user_search_index_data_reader](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.current_user_search_service_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.current_user_storage_blob_data_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_storage_blob.docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_blob) | resource |
| [azurerm_storage_data_lake_gen2_filesystem.ais_docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_data_lake_gen2_filesystem) | resource |
| [azurerm_storage_data_lake_gen2_path.tartarian](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_data_lake_gen2_path) | resource |
| [null_resource.foundry_agent](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.provision_search_index](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [null_resource.provision_search_knowledge_acl](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [random_uuid.user_impersonation_scope_id](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/uuid) | resource |
| [time_sleep.wait_project_identities](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [azuread_client_config.current](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/client_config) | data source |
| [azuread_service_principal.ai_search](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/service_principal) | data source |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ai_locations"></a> [ai\_locations](#input\_ai\_locations) | List of locations for AI Foundry instances | `list(string)` | n/a | yes |
| <a name="input_environment_name"></a> [environment\_name](#input\_environment\_name) | The name of the azd environment to be deployed | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | The supported Azure location where the resource deployed | `string` | n/a | yes |
| <a name="input_openai_chat"></a> [openai\_chat](#input\_openai\_chat) | OpenAI Chat model configuration | <pre>object({<br/>    model_name    = string<br/>    model_version = string<br/>    deploy_type   = string<br/>    capacity      = number<br/>  })</pre> | n/a | yes |
| <a name="input_openai_embedding"></a> [openai\_embedding](#input\_openai\_embedding) | OpenAI Embedding model configuration | <pre>object({<br/>    model_name    = string<br/>    model_version = string<br/>    deploy_type   = string<br/>    capacity      = number<br/>  })</pre> | n/a | yes |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Azure subscription ID | `string` | n/a | yes |
| <a name="input_knowledge_reasoning_effort"></a> [knowledge\_reasoning\_effort](#input\_knowledge\_reasoning\_effort) | Retrieval reasoning effort for Knowledge Base. Valid values: minimal, low, medium | `string` | `"medium"` | no |
| <a name="input_tpm_limit_token"></a> [tpm\_limit\_token](#input\_tpm\_limit\_token) | Tokens per minute limit for OpenAI | `number` | `30000` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_AZURE_LOCATION"></a> [AZURE\_LOCATION](#output\_AZURE\_LOCATION) | n/a |
| <a name="output_AZURE_OBO_CLIENT_ID"></a> [AZURE\_OBO\_CLIENT\_ID](#output\_AZURE\_OBO\_CLIENT\_ID) | n/a |
| <a name="output_AZURE_RESOURCE_GROUP"></a> [AZURE\_RESOURCE\_GROUP](#output\_AZURE\_RESOURCE\_GROUP) | n/a |
| <a name="output_AZURE_TENANT_ID"></a> [AZURE\_TENANT\_ID](#output\_AZURE\_TENANT\_ID) | n/a |
| <a name="output_KB_ACL_MCP_URL"></a> [KB\_ACL\_MCP\_URL](#output\_KB\_ACL\_MCP\_URL) | n/a |
| <a name="output_MODEL_DEPLOYMENT"></a> [MODEL\_DEPLOYMENT](#output\_MODEL\_DEPLOYMENT) | n/a |
| <a name="output_OPENAI_ENDPOINT"></a> [OPENAI\_ENDPOINT](#output\_OPENAI\_ENDPOINT) | n/a |
| <a name="output_PROJECT_ENDPOINT"></a> [PROJECT\_ENDPOINT](#output\_PROJECT\_ENDPOINT) | n/a |
| <a name="output_SEARCH_ENDPOINT"></a> [SEARCH\_ENDPOINT](#output\_SEARCH\_ENDPOINT) | n/a |
<!-- END_TF_DOCS -->