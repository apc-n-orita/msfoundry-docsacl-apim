#!/bin/bash

# Non-interactive argument parsing
# Usage: aif_set_sh SUBSCRIPTION_ID RESOURCE_GROUP SEARCH_SERVICE_NAME DATASOURCE_NAME STORAGE_ACCOUNT_NAME BLOB_CONTAINER_NAME BLOB_QUERY INDEX_NAME SKILLSET_NAME INDEXER_NAME

if [ $# -lt 13 ]; then
  echo "Usage: bash $0 SUBSCRIPTION_ID RESOURCE_GROUP SEARCH_SERVICE_NAME DATASOURCE_NAME STORAGE_ACCOUNT_NAME BLOB_CONTAINER_NAME BLOB_QUERY INDEX_NAME SKILLSET_NAME INDEXER_NAME RESOURCE_URI DEPLOYMENT_ID MODEL_NAME" >&2
  echo "Example: bash $0 00000000-0000-0000-0000-000000000000 my-rg mysearchsvc ds-blob mystorage rawdocs '' mainindex mainskill mainindexer https://apim-test.azure-api.net text-embedding-3-small text-embedding-3-small" >&2
  exit 1
fi

subscription_id="$1"
resource_group="$2"
search_service_name="$3"
datasource_name="$4"
storage_account_name="$5"
blob_container_name="$6"
blob_query="$7"          # pass '' for empty
index_name="$8"
skillset_name="$9"
indexer_name="${10}"
resource_uri="${11}"
deployment_id="${12}"
model_name="${13}"

# Get Azure access token
echo "Getting Azure access token..."
access_token=$(az account get-access-token --query accessToken -o tsv)

if [ -z "$access_token" ]; then
    echo "Error: Failed to get access token. Please make sure you're logged in with 'az login'"
    exit 1
fi

# ---------------------------------------------
# Azure AI Search Data Source creation (via REST)
# Docs references:
# - Create Data Source REST API: https://learn.microsoft.com/en-us/rest/api/searchservice/create-data-source
# - API versions: https://learn.microsoft.com/en-us/rest/api/searchservice/search-service-api-versions
# - RBAC (Bearer token instead of api-key): https://learn.microsoft.com/en-us/azure/search/search-security-rbac
# ---------------------------------------------


api_version="2025-11-01-preview"  # preview version required for flightingOptIn

echo "Getting Azure AI Search data plane access token (resource=https://search.azure.com)..."
search_access_token=$(az account get-access-token --resource https://search.azure.com --query accessToken -o tsv)

if [ -z "$search_access_token" ]; then
    echo "Error: Failed to get search access token. Ensure az login and proper permissions (Azure roles)." >&2
    exit 1
fi

storage_account_resource_id="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Storage/storageAccounts/${storage_account_name}"
connection_string="ResourceId=${storage_account_resource_id};"  # Managed identity style connection string

# Build JSON body for ADLS Gen2 ACL-aware datasource
datasource_body=$(cat <<EOF
{
  "name": "${datasource_name}",
  "type": "adlsgen2",
  "indexerPermissionOptions": ["groupIds"],
  "credentials": {
    "connectionString": "${connection_string}"
  },
  "container": {
    "name": "${blob_container_name}"$( [ -n "$blob_query" ] && printf ",\n    \"query\": \"%s\"" "$blob_query" )
  },
  "dataDeletionDetectionPolicy": {
    "@odata.type": "#Microsoft.Azure.Search.NativeBlobSoftDeleteDeletionDetectionPolicy"
  }
}
EOF
)

echo "Checking if data source '${datasource_name}' already exists..."
status_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${search_access_token}" \
    "https://${search_service_name}.search.windows.net/datasources('${datasource_name}')?api-version=${api_version}")

if [ "$status_code" = "200" ]; then
    echo "Data source already exists. Updating (PUT)..."
else
    echo "Data source does not exist (status $status_code). Creating (PUT)..."
fi

response=$(curl -s -D - -o /tmp/datasource_resp.json -X PUT \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${search_access_token}" \
    "https://${search_service_name}.search.windows.net/datasources('${datasource_name}')?api-version=${api_version}" \
    --data "${datasource_body}")

http_resp_code=$(echo "$response" | grep -E "^HTTP/" | tail -1 | awk '{print $2}')

echo "HTTP Response Code: ${http_resp_code}";
if [[ "$http_resp_code" != "200" && "$http_resp_code" != "201" ]]; then
    echo "Failed to create/update datasource. Full response headers + body:" >&2
    echo "$response" >&2
    echo "Body:" >&2
    cat /tmp/datasource_resp.json >&2
    echo "Cleaning up datasource temp file (error case)..." >&2
    rm -f /tmp/datasource_resp.json || echo "Warning: could not remove /tmp/datasource_resp.json" >&2
    exit 1
fi

echo "Success. Datasource JSON response:"
cat /tmp/datasource_resp.json | sed 's/\r//'

echo "Done." 
echo "Cleaning up datasource temp file..."
rm -f /tmp/datasource_resp.json || echo "Warning: could not remove /tmp/datasource_resp.json" >&2

# ---------------------------------------------
# Azure AI Search Index creation/update (via REST)
# Docs references consulted:
# - Create or Update Index: https://learn.microsoft.com/en-us/rest/api/searchservice/indexes/create-or-update
# - Semantic configuration: https://learn.microsoft.com/en-us/azure/search/semantic-how-to-configure
# - Field definitions: https://learn.microsoft.com/en-us/azure/search/search-how-to-create-search-index#configure-field-definitions
# ---------------------------------------------


echo "Building index definition JSON..."
index_body=$(cat <<EOF
{
  "name": "${index_name}",
  "description": "Search index for knowledge source 'tartalia'. has acl fields.",
  "permissionFilterOption": "enabled",
  "fields": [
    {"name": "uid", "type": "Edm.String", "searchable": true, "filterable": false, "retrievable": true, "stored": true, "sortable": true, "facetable": false, "key": true, "analyzer": "keyword", "synonymMaps": []},
    {"name": "snippet_parent_id", "type": "Edm.String", "searchable": false, "filterable": true, "retrievable": true, "stored": true, "sortable": false, "facetable": false, "key": false, "synonymMaps": []},
    {"name": "blob_url", "type": "Edm.String", "searchable": false, "filterable": true, "retrievable": true, "stored": true, "sortable": false, "facetable": false, "key": false, "synonymMaps": []},
    {"name": "snippet", "type": "Edm.String", "searchable": true, "filterable": false, "retrievable": true, "stored": true, "sortable": false, "facetable": false, "key": false, "synonymMaps": []},
    {"name": "image_snippet_parent_id", "type": "Edm.String", "searchable": false, "filterable": true, "retrievable": true, "stored": true, "sortable": false, "facetable": false, "key": false, "synonymMaps": []},
    {"name": "snippet_vector", "type": "Collection(Edm.Single)", "searchable": true, "filterable": false, "retrievable": true, "stored": true, "sortable": false, "facetable": false, "key": false, "dimensions": 1536, "vectorSearchProfile": "tartalia-vector-search-profile", "synonymMaps": []},
    {"name": "title", "type": "Edm.String", "searchable": true, "filterable": false, "retrievable": true, "stored": true, "sortable": false, "facetable": false, "key": false, "analyzer": "standard.lucene", "synonymMaps": []},
    {"name": "metadata_storage_name", "type": "Edm.String", "searchable": true, "filterable": true, "retrievable": true, "stored": true, "sortable": true, "facetable": false, "key": false, "analyzer": "standard.lucene", "synonymMaps": []},
    {"name": "UserIds", "type": "Collection(Edm.String)", "searchable": true, "filterable": true, "retrievable": true, "stored": true, "sortable": false, "facetable": true, "key": false, "permissionFilter": "userIds", "synonymMaps": []},
    {"name": "GroupIds", "type": "Collection(Edm.String)", "searchable": true, "filterable": true, "retrievable": true, "stored": true, "sortable": false, "facetable": true, "key": false, "permissionFilter": "groupIds", "synonymMaps": []},
    {"name": "RbacScope", "type": "Edm.String", "searchable": true, "filterable": true, "retrievable": true, "stored": true, "sortable": true, "facetable": true, "key": false, "permissionFilter": "rbacScope", "synonymMaps": []},
    {"name": "metadata_storage_path", "type": "Edm.String", "searchable": false, "filterable": true, "retrievable": true, "stored": true, "sortable": false, "facetable": false, "key": false, "synonymMaps": []}
  ],
  "scoringProfiles": [],
  "suggesters": [],
  "analyzers": [],
  "normalizers": [],
  "tokenizers": [],
  "tokenFilters": [],
  "charFilters": [],
  "similarity": {"@odata.type": "#Microsoft.Azure.Search.BM25Similarity"},
  "semantic": {
    "defaultConfiguration": "tartalia-semantic-configuration",
    "configurations": [
      {
        "name": "tartalia-semantic-configuration",
        "flightingOptIn": false,
        "rankingOrder": "BoostedRerankerScore",
        "prioritizedFields": {
          "titleField": {"fieldName": "title"},
          "prioritizedContentFields": [{"fieldName": "snippet"}],
          "prioritizedKeywordsFields": []
        }
      }
    ]
  },
  "vectorSearch": {
    "algorithms": [
      {
        "name": "tartalia-vector-search-algorithm",
        "kind": "hnsw",
        "hnswParameters": {"metric": "cosine", "m": 4, "efConstruction": 400, "efSearch": 500}
      }
    ],
    "profiles": [
      {
        "name": "tartalia-vector-search-profile",
        "algorithm": "tartalia-vector-search-algorithm",
        "vectorizer": "tartalia-vectorizer",
        "compression": "tartalia-vector-search-scalar-quantization"
      }
    ],
    "vectorizers": [
      {
        "name": "tartalia-vectorizer",
        "kind": "azureOpenAI",
        "azureOpenAIParameters": {
          "resourceUri": "${resource_uri}",
          "deploymentId": "${deployment_id}",
          "modelName": "${model_name}"
        }
      }
    ],
    "compressions": [
      {
        "name": "tartalia-vector-search-scalar-quantization",
        "kind": "scalarQuantization",
        "scalarQuantizationParameters": {"quantizedDataType": "int8"},
        "rescoringOptions": {"enableRescoring": true, "defaultOversampling": 4, "rescoreStorageMethod": "preserveOriginals"}
      }
    ]
  }
}
EOF
)

echo "Checking if index '${index_name}' exists..."
index_status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${search_access_token}" \
    "https://${search_service_name}.search.windows.net/indexes('${index_name}')?api-version=${api_version}")

if [ "$index_status" = "200" ]; then
    echo "Index exists. Updating (PUT)..."
else
    echo "Index not found (status $index_status). Creating (PUT)..."
fi

index_response=$(curl -s -D - -o /tmp/index_resp.json -X PUT \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${search_access_token}" \
    "https://${search_service_name}.search.windows.net/indexes('${index_name}')?allowIndexDowntime=true&api-version=${api_version}" \
    --data "${index_body}")

index_http_code=$(echo "$index_response" | grep -E "^HTTP/" | tail -1 | awk '{print $2}')
echo "Index HTTP Response Code: ${index_http_code}"
if [[ "$index_http_code" != "200" && "$index_http_code" != "201" ]]; then
    echo "Failed to create/update index. Headers + body:" >&2
    echo "$index_response" >&2
    echo "Body:" >&2
    cat /tmp/index_resp.json >&2
    echo "Cleaning up index temp file (error case)..." >&2
    rm -f /tmp/index_resp.json || echo "Warning: could not remove /tmp/index_resp.json" >&2
    exit 1
fi

echo "Success. Index response JSON:"
cat /tmp/index_resp.json | sed 's/\r//'

echo "Index provisioning step completed."
echo "Cleaning up index temp file..."
rm -f /tmp/index_resp.json || echo "Warning: could not remove /tmp/index_resp.json" >&2

# ---------------------------------------------
# Azure AI Search Skillset creation/update (via REST)
# Docs references consulted:
# - Create Skillset: https://learn.microsoft.com/en-us/rest/api/searchservice/skillsets/create
# - Skillset definition & skills: https://learn.microsoft.com/en-us/azure/search/cognitive-search-defining-skillset#add-a-skillset-definition
# ---------------------------------------------


echo "Building skillset JSON definition..."
skillset_body=$(cat <<EOF
{
  "name": "${skillset_name}",
  "description": "Skillset for knowledge source 'tartalia-acl' - text processing only",
  "skills": [
    {
      "@odata.type": "#Microsoft.Skills.Text.SplitSkill",
      "name": "SplitSkill",
      "description": "Split document content into chunks",
      "context": "/document",
      "defaultLanguageCode": "en",
      "textSplitMode": "pages",
      "maximumPageLength": 2000,
      "pageOverlapLength": 200,
      "maximumPagesToTake": 0,
      "unit": "characters",
      "inputs": [{"name": "text", "source": "/document/content", "inputs": []}],
      "outputs": [{"name": "textItems", "targetName": "pages"}]
    },
    {
      "@odata.type": "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill",
      "name": "AzureOpenAIEmbeddingSkill",
      "description": "Generate embeddings",
      "context": "/document/pages/*",
      "resourceUri": "${resource_uri}",
      "deploymentId": "${deployment_id}",
      "dimensions": 1536,
      "modelName": "${model_name}",
      "inputs": [{"name": "text", "source": "/document/pages/*", "inputs": []}],
      "outputs": [{"name": "embedding", "targetName": "text_vector"}]
    }
  ],
  "indexProjections": {
    "selectors": [
      {
        "targetIndexName": "${index_name}",
        "parentKeyFieldName": "snippet_parent_id",
        "sourceContext": "/document/pages/*",
        "mappings": [
          {"name": "snippet_vector", "source": "/document/pages/*/text_vector", "inputs": []},
          {"name": "snippet", "source": "/document/pages/*", "inputs": []},
          {"name": "metadata_storage_path", "source": "/document/metadata_storage_path", "inputs": []},
          {"name": "title", "source": "/document/title", "inputs": []},
          {"name": "metadata_storage_name", "source": "/document/metadata_storage_name", "inputs": []},
          {"name": "GroupIds", "source": "/document/metadata_group_ids", "inputs": []}
        ]
      }
    ],
    "parameters": {"projectionMode": "skipIndexingParentDocuments"}
  }
}
EOF
)

echo "Checking if skillset '${skillset_name}' exists..."
skillset_status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${search_access_token}" \
    "https://${search_service_name}.search.windows.net/skillsets('${skillset_name}')?api-version=${api_version}")

if [ "$skillset_status" = "200" ]; then
    echo "Skillset exists. Updating (PUT)..."
else
    echo "Skillset not found (status $skillset_status). Creating (PUT)..."
fi

skillset_response=$(curl -s -D - -o /tmp/skillset_resp.json -X PUT \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${search_access_token}" \
    "https://${search_service_name}.search.windows.net/skillsets('${skillset_name}')?api-version=${api_version}" \
    --data "${skillset_body}")

skillset_http_code=$(echo "$skillset_response" | grep -E "^HTTP/" | tail -1 | awk '{print $2}')
echo "Skillset HTTP Response Code: ${skillset_http_code}"
if [[ "$skillset_http_code" != "200" && "$skillset_http_code" != "201" ]]; then
    echo "Failed to create/update skillset. Headers + body:" >&2
    echo "$skillset_response" >&2
    echo "Body:" >&2
    cat /tmp/skillset_resp.json >&2
    echo "Cleaning up skillset temp file (error case)..." >&2
    rm -f /tmp/skillset_resp.json || echo "Warning: could not remove /tmp/skillset_resp.json" >&2
    exit 1
fi

echo "Success. Skillset response JSON:"
cat /tmp/skillset_resp.json | sed 's/\r//'

echo "Skillset provisioning step completed."
echo "Cleaning up skillset temp file..."
rm -f /tmp/skillset_resp.json || echo "Warning: could not remove /tmp/skillset_resp.json" >&2

# ---------------------------------------------
# Azure AI Search Indexer creation/update (via REST)
# Docs references consulted:
# - Create Indexer: https://learn.microsoft.com/en-us/rest/api/searchservice/indexers/create
# - Field mappings functions (base64Encode): https://learn.microsoft.com/en-us/azure/search/search-indexer-field-mappings#mapping-functions-and-examples
# - Indexer request body parameters: https://learn.microsoft.com/en-us/rest/api/searchservice/create-indexer#request-body
# ---------------------------------------------


echo "Building indexer JSON definition..."
indexer_body=$(cat <<EOF
{
  "name": "${indexer_name}",
  "dataSourceName": "${datasource_name}",
  "skillsetName": "${skillset_name}",
  "targetIndexName": "${index_name}",
  "parameters": {
    "maxFailedItems": -1,
    "maxFailedItemsPerBatch": -1,
    "configuration": {}
  },
  "fieldMappings": [
    {
      "sourceFieldName": "metadata_group_ids",
      "targetFieldName": "GroupIds"
    },
    {
      "sourceFieldName": "metadata_storage_name",
      "targetFieldName": "title"
    },
    {
      "sourceFieldName": "metadata_storage_path",
      "targetFieldName": "snippet_parent_id",
      "mappingFunction": {
        "name": "base64Encode",
        "parameters": {"useHttpServerUtilityUrlTokenEncode": false}
      }
    }
  ],
  "outputFieldMappings": []
}
EOF
)

echo "Checking if indexer '${indexer_name}' exists..."
indexer_status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${search_access_token}" \
    "https://${search_service_name}.search.windows.net/indexers('${indexer_name}')?api-version=${api_version}")

if [ "$indexer_status" = "200" ]; then
    echo "Indexer exists. Updating (PUT)..."
else
    echo "Indexer not found (status $indexer_status). Creating (PUT)..."
fi

indexer_response=$(curl -s -D - -o /tmp/indexer_resp.json -X PUT \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${search_access_token}" \
    "https://${search_service_name}.search.windows.net/indexers('${indexer_name}')?api-version=${api_version}" \
    --data "${indexer_body}")

indexer_http_code=$(echo "$indexer_response" | grep -E "^HTTP/" | tail -1 | awk '{print $2}')
echo "Indexer HTTP Response Code: ${indexer_http_code}"
if [[ "$indexer_http_code" != "200" && "$indexer_http_code" != "201" ]]; then
    echo "Failed to create/update indexer. Headers + body:" >&2
    echo "$indexer_response" >&2
    echo "Body:" >&2
    cat /tmp/indexer_resp.json >&2
    echo "Cleaning up indexer temp file (error case)..." >&2
    rm -f /tmp/indexer_resp.json || echo "Warning: could not remove /tmp/indexer_resp.json" >&2
    exit 1
fi

echo "Success. Indexer response JSON:"
cat /tmp/indexer_resp.json | sed 's/\r//'

echo "Indexer provisioning step completed."
echo "Cleaning up indexer temp file..."
rm -f /tmp/indexer_resp.json || echo "Warning: could not remove /tmp/indexer_resp.json" >&2
