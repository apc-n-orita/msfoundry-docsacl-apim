<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_azurecaf"></a> [azurecaf](#requirement\_azurecaf) | ~>1.2.24 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~>4.42.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurecaf"></a> [azurecaf](#provider\_azurecaf) | ~>1.2.24 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | ~>4.42.0 |

## Resources

| Name | Type |
|------|------|
| [azurecaf_name.applicationinsights_name](https://registry.terraform.io/providers/aztfmod/azurecaf/latest/docs/resources/name) | resource |
| [azurerm_application_insights.applicationinsights](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_insights) | resource |
| [azurerm_portal_dashboard.board](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/portal_dashboard) | resource |
| [azurerm_subscription.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/subscription) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_environment_name"></a> [environment\_name](#input\_environment\_name) | The name of the environment to be deployed | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | The supported Azure location where the resource deployed | `string` | n/a | yes |
| <a name="input_resource_token"></a> [resource\_token](#input\_resource\_token) | A suffix string to centrally mitigate resource name collisions. | `string` | n/a | yes |
| <a name="input_rg_name"></a> [rg\_name](#input\_rg\_name) | The name of the resource group to deploy resources into | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | A list of tags used for deployed services. | `map(string)` | n/a | yes |
| <a name="input_workspace_id"></a> [workspace\_id](#input\_workspace\_id) | The name of the Azure log analytics workspace | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_APPLICATIONINSIGHTS_CONNECTION_STRING"></a> [APPLICATIONINSIGHTS\_CONNECTION\_STRING](#output\_APPLICATIONINSIGHTS\_CONNECTION\_STRING) | n/a |
| <a name="output_APPLICATIONINSIGHTS_INSTRUMENTATION_KEY"></a> [APPLICATIONINSIGHTS\_INSTRUMENTATION\_KEY](#output\_APPLICATIONINSIGHTS\_INSTRUMENTATION\_KEY) | n/a |
| <a name="output_APPLICATIONINSIGHTS_NAME"></a> [APPLICATIONINSIGHTS\_NAME](#output\_APPLICATIONINSIGHTS\_NAME) | n/a |
<!-- END_TF_DOCS -->