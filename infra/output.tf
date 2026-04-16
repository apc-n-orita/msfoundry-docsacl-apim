# Declare output values for the main terraform module.
#
# This allows the main terraform module outputs to be referenced by other modules,
# or by the local machine as a way to reference created resources in Azure for local development.
# Secrets should not be added here.
#
# Outputs are automatically saved in the local azd environment .env file.
# To see these outputs, run `azd env get-values`. `azd env get-values --output json` for json output.

output "AZURE_LOCATION" {
  value = var.location
}

output "AZURE_TENANT_ID" {
  value = data.azurerm_client_config.current.tenant_id
}

output "AZURE_RESOURCE_GROUP" {
  value = azurerm_resource_group.rg.name
}

output "PROJECT_ENDPOINT" {
  value = "${module.apim.gateway_url}/foundryagent/api/projects/aiproject"
}

output "OPENAI_ENDPOINT" {
  value = "${module.apim.gateway_url}/"
}

output "SEARCH_ENDPOINT" {
  value = "https://${module.ai_search.search_service_name}.search.windows.net"
}

output "KB_ACL_MCP_URL" {
  value = "https://${module.ai_search.search_service_name}.search.windows.net/knowledgebases/kb-tartalia-acl-gen2/mcp?api-version=2025-11-01-Preview"
}

output "AZURE_OBO_CLIENT_ID" {
  value = azuread_application.oauth_app.client_id
}

output "MODEL_DEPLOYMENT" {
  value = var.openai_chat.model_name
}
