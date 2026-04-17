#!/bin/bash

# Delete Azure AI Search resources created by ais_set_knowledge.sh
# Deletes in reverse dependency order: Knowledge Base → Knowledge Source
#
# Usage: bash ais_delete_knowledge.sh SEARCH_SERVICE_NAME KNOWLEDGE_BASE_NAME KNOWLEDGE_SOURCE_NAME
# Example: bash ais_delete_knowledge.sh mysearchsvc myknowledgebase tartalia-acl-groups
#
# Use this script to clean up when null_resource.provision_search_knowledge_acl fails
# and a full reset is needed before re-running azd up.
#
# REST API references:
# - Delete Knowledge Base:   https://learn.microsoft.com/en-us/rest/api/searchservice/knowledge-bases/delete?view=rest-searchservice-2025-11-01-preview
# - Delete Knowledge Source: https://learn.microsoft.com/en-us/rest/api/searchservice/knowledge-sources/delete?view=rest-searchservice-2025-11-01-preview
# - RBAC (Bearer token): https://learn.microsoft.com/en-us/azure/search/search-security-rbac

if [ $# -lt 3 ]; then
  echo "Usage: bash $0 SEARCH_SERVICE_NAME KNOWLEDGE_BASE_NAME KNOWLEDGE_SOURCE_NAME" >&2
  echo "Example: bash $0 mysearchsvc myknowledgebase tartalia-acl-groups" >&2
  exit 1
fi

search_service_name="$1"
knowledge_base_name="$2"
knowledge_source_name="$3"

api_version="2025-11-01-preview"
base_url="https://${search_service_name}.search.windows.net"

echo "Getting Azure AI Search data plane access token (resource=https://search.azure.com)..."
search_access_token=$(az account get-access-token --resource https://search.azure.com --query accessToken -o tsv)

if [ -z "$search_access_token" ]; then
    echo "Error: Failed to get search access token. Ensure az login and proper permissions (Azure roles)." >&2
    exit 1
fi

# Helper: DELETE a resource; treat 204 (deleted) and 404 (not found) as success
delete_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local endpoint="${base_url}/${resource_type}('${resource_name}')?api-version=${api_version}"

    echo ""
    echo "Deleting ${resource_type}: '${resource_name}'..."
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
        -H "Authorization: Bearer ${search_access_token}" \
        "${endpoint}")

    if [ "$http_code" = "204" ]; then
        echo "  -> Deleted successfully (204 No Content)."
    elif [ "$http_code" = "404" ]; then
        echo "  -> Not found (404), skipping."
    else
        echo "  -> Unexpected response: HTTP ${http_code}" >&2
        echo "     Endpoint: ${endpoint}" >&2
        return 1
    fi
}

# Delete in reverse dependency order (knowledge base references knowledge source)
delete_resource "knowledgebases"  "${knowledge_base_name}"  || exit 1
delete_resource "knowledgesources" "${knowledge_source_name}" || exit 1

echo ""
echo "All knowledge resources deleted. You can now re-run azd up or ais_set_knowledge.sh."
