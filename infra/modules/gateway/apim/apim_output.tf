output "APIM_SERVICE_NAME" {
  value = azurerm_api_management.apim.name
}

output "API_MANAGEMENT_LOGGER_ID" {
  value = azapi_resource.apim_logger.id
}

output "gateway_url" {
  value = azurerm_api_management.apim.gateway_url
}

output "APIM_MANAGED_IDENTITY_PRINCIPAL_ID" {
  value = azurerm_api_management.apim.identity[0].principal_id

}

output "APIM_SERVICE_ID" {
  value = azurerm_api_management.apim.id
}
