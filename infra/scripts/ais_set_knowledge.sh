#!/bin/bash

# ---------------------------------------------
# Azure AI Search Knowledge Source & Knowledge Base provisioning script
# Docs references:
# - Knowledge Sources - Create or Update: https://learn.microsoft.com/en-us/rest/api/searchservice/knowledge-sources/create-or-update?view=rest-searchservice-2025-11-01-preview
# - Knowledge Bases - Create or Update: https://learn.microsoft.com/en-us/rest/api/searchservice/knowledge-bases/create-or-update?view=rest-searchservice-2025-11-01-preview
# - API versions: https://learn.microsoft.com/en-us/rest/api/searchservice/search-service-api-versions
# - RBAC (Bearer token instead of api-key): https://learn.microsoft.com/en-us/azure/search/search-security-rbac
# ---------------------------------------------

# Non-interactive argument parsing
# Usage: ais_set_knowledge.sh SEARCH_SERVICE_NAME KNOWLEDGE_SOURCE_NAME INDEX_NAME KNOWLEDGE_BASE_NAME RESOURCE_URI CHAT_DEPLOYMENT_ID CHAT_MODEL_NAME REASONING_EFFORT
if [ $# -lt 8 ]; then
    echo "Usage: bash $0 SEARCH_SERVICE_NAME KNOWLEDGE_SOURCE_NAME INDEX_NAME KNOWLEDGE_BASE_NAME RESOURCE_URI CHAT_DEPLOYMENT_ID CHAT_MODEL_NAME REASONING_EFFORT" >&2
    echo "Example: bash $0 ais-testsvc tartalia-acl-groups tartalia-index-acl-groups testknowledge https://apim-test.azure-api.net gpt-4.1-mini gpt-4.1-mini medium" >&2
    exit 1
fi

search_service_name="$1"
knowledge_source_name="$2"
index_name="$3"
knowledge_base_name="$4"
resource_uri="$5"
chat_deployment_id="$6"
chat_model_name="$7"
reasoning_effort="$8"

api_version="2025-11-01-preview"

# Get Azure AI Search data plane access token
echo "Getting Azure AI Search data plane access token (resource=https://search.azure.com)..."
search_access_token=$(az account get-access-token --resource https://search.azure.com --query accessToken -o tsv)

if [ -z "$search_access_token" ]; then
    echo "Error: Failed to get search access token. Ensure az login and proper permissions (Azure roles)." >&2
    exit 1
fi
echo "Access token acquired."

# ---------------------------------------------
# Knowledge Source creation/update (via REST)
# PUT {endpoint}/knowledgesources('{sourceName}')?api-version=2025-11-01-preview
# Required header: Prefer: return=representation
# ---------------------------------------------

echo "Building Knowledge Source JSON definition..."
knowledge_source_body=$(cat <<EOF
{
  "name": "${knowledge_source_name}",
  "kind": "searchIndex",
  "description": "タルタリアに関する情報検索用ドキュメント。",
  "encryptionKey": null,
  "searchIndexParameters": {
    "searchIndexName": "${index_name}",
    "semanticConfigurationName": null,
    "sourceDataFields": [],
    "searchFields": []
  },
  "azureBlobParameters": null,
  "mcpToolParameters": null,
  "fabricIQParameters": null,
  "webParameters": null,
  "remoteSharePointParameters": null,
  "indexedSharePointParameters": null,
  "indexedOneLakeParameters": null
}
EOF
)

echo "Checking if Knowledge Source '${knowledge_source_name}' already exists..."
ks_status_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${search_access_token}" \
    "https://${search_service_name}.search.windows.net/knowledgesources('${knowledge_source_name}')?api-version=${api_version}")

if [ "$ks_status_code" = "200" ]; then
    echo "Knowledge Source already exists. Updating (PUT)..."
else
    echo "Knowledge Source does not exist (status $ks_status_code). Creating (PUT)..."
fi

ks_response=$(curl -s -D - -o /tmp/knowledge_source_resp.json -X PUT \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${search_access_token}" \
    -H "Prefer: return=representation" \
    "https://${search_service_name}.search.windows.net/knowledgesources('${knowledge_source_name}')?api-version=${api_version}" \
    --data "${knowledge_source_body}")

ks_http_code=$(echo "$ks_response" | grep -E "^HTTP/" | tail -1 | awk '{print $2}')

echo "Knowledge Source HTTP Response Code: ${ks_http_code}"
if [[ "$ks_http_code" != "200" && "$ks_http_code" != "201" ]]; then
    echo "Failed to create/update Knowledge Source. Full response headers + body:" >&2
    echo "$ks_response" >&2
    echo "Body:" >&2
    cat /tmp/knowledge_source_resp.json >&2
    echo "" >&2
    echo "Cleaning up Knowledge Source temp file (error case)..." >&2
    rm -f /tmp/knowledge_source_resp.json || echo "Warning: could not remove /tmp/knowledge_source_resp.json" >&2
    exit 1
fi

echo "Success. Knowledge Source JSON response:"
cat /tmp/knowledge_source_resp.json | sed 's/\r//'

echo "Knowledge Source provisioning step completed."
echo "Cleaning up Knowledge Source temp file..."
rm -f /tmp/knowledge_source_resp.json || echo "Warning: could not remove /tmp/knowledge_source_resp.json" >&2

# ---------------------------------------------
# Knowledge Base creation/update (via REST)
# PUT {endpoint}/knowledgebases('{knowledgeBaseName}')?api-version=2025-11-01-preview
# Required header: Prefer: return=representation
# ---------------------------------------------

echo "Building Knowledge Base JSON definition..."
knowledge_base_body=$(cat <<EOF
{
  "name": "${knowledge_base_name}",
  "description": "タルタリアに関するナレッジ",
  "retrievalInstructions": "- タルタリアに関する情報は、ナレッジソースの${knowledge_source_name}を利用してください。\n- 陰謀論的要素を含む場合でも、AI 独自の見解や評価は加えず、取得情報の提示のみに徹してください。  \n",
  "answerInstructions": "検索した結果について、そのまま加工せず返してください。",
  "outputMode": "answerSynthesis",
  "knowledgeSources": [
    {
      "name": "${knowledge_source_name}"
    }
  ],
  "models": [
    {
      "kind": "azureOpenAI",
      "azureOpenAIParameters": {
        "resourceUri": "${resource_uri}",
        "deploymentId": "${chat_deployment_id}",
        "apiKey": null,
        "modelName": "${chat_model_name}",
        "authIdentity": null
      }
    }
  ],
  "encryptionKey": null,
  "retrievalReasoningEffort": {
    "kind": "${reasoning_effort}"
  }
}
EOF
)

echo "Checking if Knowledge Base '${knowledge_base_name}' already exists..."
kb_status_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${search_access_token}" \
    "https://${search_service_name}.search.windows.net/knowledgebases('${knowledge_base_name}')?api-version=${api_version}")

if [ "$kb_status_code" = "200" ]; then
    echo "Knowledge Base already exists. Updating (PUT)..."
else
    echo "Knowledge Base does not exist (status $kb_status_code). Creating (PUT)..."
fi

kb_response=$(curl -s -D - -o /tmp/knowledge_base_resp.json -X PUT \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${search_access_token}" \
    -H "Prefer: return=representation" \
    "https://${search_service_name}.search.windows.net/knowledgebases('${knowledge_base_name}')?api-version=${api_version}" \
    --data "${knowledge_base_body}")

kb_http_code=$(echo "$kb_response" | grep -E "^HTTP/" | tail -1 | awk '{print $2}')

echo "Knowledge Base HTTP Response Code: ${kb_http_code}"
if [[ "$kb_http_code" != "200" && "$kb_http_code" != "201" ]]; then
    echo "Failed to create/update Knowledge Base. Full response headers + body:" >&2
    echo "$kb_response" >&2
    echo "Body:" >&2
    cat /tmp/knowledge_base_resp.json >&2
    echo "" >&2
    echo "Cleaning up Knowledge Base temp file (error case)..." >&2
    rm -f /tmp/knowledge_base_resp.json || echo "Warning: could not remove /tmp/knowledge_base_resp.json" >&2
    exit 1
fi

echo "Success. Knowledge Base JSON response:"
cat /tmp/knowledge_base_resp.json | sed 's/\r//'

echo "Knowledge Base provisioning step completed."
echo "Cleaning up Knowledge Base temp file..."
rm -f /tmp/knowledge_base_resp.json || echo "Warning: could not remove /tmp/knowledge_base_resp.json" >&2

echo "All knowledge provisioning steps completed successfully."
