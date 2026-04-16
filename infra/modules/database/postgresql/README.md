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
| <a name="provider_random"></a> [random](#provider\_random) | n/a |

## Resources

| Name | Type |
|------|------|
| [azurecaf_name.psql_name](https://registry.terraform.io/providers/aztfmod/azurecaf/latest/docs/resources/name) | resource |
| [azurerm_postgresql_flexible_server.psql_server](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server) | resource |
| [azurerm_postgresql_flexible_server_database.database](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server_database) | resource |
| [azurerm_postgresql_flexible_server_firewall_rule.firewall_rule](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server_firewall_rule) | resource |
| [azurerm_resource_deployment_script_azure_cli.psql-script](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_deployment_script_azure_cli) | resource |
| [random_password.password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_location"></a> [location](#input\_location) | The supported Azure location where the resource deployed | `string` | n/a | yes |
| <a name="input_resource_token"></a> [resource\_token](#input\_resource\_token) | A suffix string to centrally mitigate resource name collisions. | `string` | n/a | yes |
| <a name="input_rg_name"></a> [rg\_name](#input\_rg\_name) | The name of the resource group to deploy resources into | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | A list of tags used for deployed services. | `map(string)` | n/a | yes |
| <a name="input_administrator_login"></a> [administrator\_login](#input\_administrator\_login) | The PostgreSQL administrator login | `string` | `"psqladmin"` | no |
| <a name="input_database_name"></a> [database\_name](#input\_database\_name) | The database name of PostgreSQL | `string` | `"todo"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_AZURE_POSTGRESQL_DATABASE_NAME"></a> [AZURE\_POSTGRESQL\_DATABASE\_NAME](#output\_AZURE\_POSTGRESQL\_DATABASE\_NAME) | n/a |
| <a name="output_AZURE_POSTGRESQL_FQDN"></a> [AZURE\_POSTGRESQL\_FQDN](#output\_AZURE\_POSTGRESQL\_FQDN) | n/a |
| <a name="output_AZURE_POSTGRESQL_PASSWORD"></a> [AZURE\_POSTGRESQL\_PASSWORD](#output\_AZURE\_POSTGRESQL\_PASSWORD) | n/a |
| <a name="output_AZURE_POSTGRESQL_SPRING_DATASOURCE_URL"></a> [AZURE\_POSTGRESQL\_SPRING\_DATASOURCE\_URL](#output\_AZURE\_POSTGRESQL\_SPRING\_DATASOURCE\_URL) | n/a |
| <a name="output_AZURE_POSTGRESQL_USERNAME"></a> [AZURE\_POSTGRESQL\_USERNAME](#output\_AZURE\_POSTGRESQL\_USERNAME) | n/a |
<!-- END_TF_DOCS -->