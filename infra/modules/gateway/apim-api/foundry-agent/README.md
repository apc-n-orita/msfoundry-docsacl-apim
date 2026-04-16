<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | ~>2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~>4.42.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | ~>2.0.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~>4.42.0 |

## Resources

| Name | Type |
|------|------|
| [azapi_resource.apim_foundryagent_api_diagnostic_monitor](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.backend_pool](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.foundry_backend](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_api_management_api.foundryagent](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api) | resource |
| [azurerm_api_management_api_diagnostic.foundryagent](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_diagnostic) | resource |
| [azurerm_api_management_api_policy.foundryagent](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_api_policy) | resource |
| [azurerm_api_management_named_value.aif_backend_pool](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.entra_id_group](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_named_value.entra_id_tenant_id](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_named_value) | resource |
| [azurerm_api_management_product.foundryagent](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product) | resource |
| [azurerm_api_management_product_api.foundryagent](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product_api) | resource |
| [azurerm_api_management_product_policy.foundryagent](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/api_management_product_policy) | resource |
| [azurerm_role_assignment.foundryagent](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ai_model_deploymentname"></a> [ai\_model\_deploymentname](#input\_ai\_model\_deploymentname) | AI model deployment name | `string` | n/a | yes |
| <a name="input_api_management_id"></a> [api\_management\_id](#input\_api\_management\_id) | API Management resource ID (for backend parent\_id) | `string` | n/a | yes |
| <a name="input_api_management_logger_id"></a> [api\_management\_logger\_id](#input\_api\_management\_logger\_id) | n/a | `string` | n/a | yes |
| <a name="input_api_management_name"></a> [api\_management\_name](#input\_api\_management\_name) | n/a | `any` | n/a | yes |
| <a name="input_apim_gateway_url"></a> [apim\_gateway\_url](#input\_apim\_gateway\_url) | API Management Gateway URL (for OpenAPI template) | `string` | n/a | yes |
| <a name="input_apim_principal_id"></a> [apim\_principal\_id](#input\_apim\_principal\_id) | Principal ID for role assignment (APIM managed identity) | `string` | n/a | yes |
| <a name="input_entra_app_group_id"></a> [entra\_app\_group\_id](#input\_entra\_app\_group\_id) | Entra ID group ID for API policy | `string` | n/a | yes |
| <a name="input_entra_app_tenant_id"></a> [entra\_app\_tenant\_id](#input\_entra\_app\_tenant\_id) | Entra ID tenant ID for API policy | `string` | n/a | yes |
| <a name="input_foundry_backend_ids"></a> [foundry\_backend\_ids](#input\_foundry\_backend\_ids) | Set of Foundry backend resource IDs for role assignment scope | `list(string)` | n/a | yes |
| <a name="input_foundry_backend_names"></a> [foundry\_backend\_names](#input\_foundry\_backend\_names) | List of Foundry backend names (e.g. ['aif-env-001', 'aif-env-002']) | `list(string)` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | n/a | `any` | n/a | yes |
| <a name="input_tpm_limit_token"></a> [tpm\_limit\_token](#input\_tpm\_limit\_token) | Tokens per minute limit | `number` | `30000` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_api_id"></a> [api\_id](#output\_api\_id) | n/a |
<!-- END_TF_DOCS -->