# Azure AI Search ドキュメントACL設定ガイド

**最終更新**: 2026年3月  
**API バージョン**: 2025-11-01-preview

## 目次

1. [概要](#概要)
2. [2つのアプローチ比較](#2つのアプローチ比較)
3. [前提条件](#前提条件)
4. [アプローチ1: Knowledge Source（推奨・簡単）](#アプローチ1-knowledge-source推奨簡単)
5. [アプローチ2: Indexer直接使用（高度・柔軟）](#アプローチ2-indexer直接使用高度柔軟)
6. [ADLS Gen2 ACL設定](#adls-gen2-acl設定)
7. [クエリ実行](#クエリ実行)
8. [権限同期とメンテナンス](#権限同期とメンテナンス)
9. [トラブルシューティング](#トラブルシューティング)
10. [ベストプラクティス](#ベストプラクティス)

---

## 概要

Azure AI SearchのドキュメントレベルACL（アクセス制御リスト）により、**ADLS Gen2のPOSIX-like ACL**を検索インデックスに取り込み、ユーザーの権限に基づいて検索結果を自動的にフィルタリングできます。

### 主な機能

- ✅ ファイル/ディレクトリレベルのACL自動取得
- ✅ Microsoft Entra IDグループ・ユーザー認証
- ✅ クエリ時の自動権限チェック
- ✅ 権限のないドキュメントを自動除外

### サポート対象

| データソース       | ACLサポート                  | RBACサポート    |
| ------------------ | ---------------------------- | --------------- |
| **ADLS Gen2**      | ✅ ファイル/ディレクトリ単位 | ✅ コンテナ単位 |
| Azure Blob Storage | ❌                           | ✅ コンテナ単位 |
| SharePoint 365     | ✅ ドキュメント単位          | -               |

---

## 2つのアプローチ比較

### 比較表

| 項目                       | Knowledge Source      | Indexer直接使用      |
| -------------------------- | --------------------- | -------------------- |
| **難易度**                 | ⭐ 簡単               | ⭐⭐⭐ 高度          |
| **インデックスフィールド** | ✅ 自動生成           | ❌ 手動定義必須      |
| **fieldMappings**          | ✅ 自動設定           | ❌ 手動設定必須      |
| **データソース**           | ✅ 自動生成           | ❌ 手動作成必須      |
| **カスタマイズ性**         | ❌ 制限あり           | ✅ 完全制御可能      |
| **スキルセット**           | ✅ 自動生成可能       | 任意                 |
| **推奨ケース**             | シンプルなACL取り込み | 複雑な要件・既存統合 |

### どちらを選ぶべきか？

**Knowledge Sourceを選ぶ場合**:

- ACL/RBAC取り込みだけが目的
- 新規プロジェクト
- 迅速な導入が必要
- カスタマイズ不要

**Indexer直接使用を選ぶ場合**:

- カスタムスキルセットが必要
- 既存インデックスへの統合
- 細かいフィールド制御が必要
- 複数データソースの統合

---

## 前提条件

### 1. Azure AI Search

```bash
# 必要な設定
- Tier: Basic以上（Managed Identity対応）
- API Version: 2025-11-01-preview以上
- Managed Identity: 有効化（System or User Assigned）
- RBAC: 有効化
```

**必要なRBACロール（開発者）**:

- `Search Service Contributor` - オブジェクト作成
- `Search Index Data Contributor` - データインポート
- `Search Index Data Reader` - クエリ実行

### 2. ADLS Gen2 ストレージアカウント

```bash
# 必須設定
- Hierarchical Namespace (HNS): 有効
- API Endpoint: dfs.core.windows.net
```

**必要なRBACロール（Search Service）**:

- `Storage Blob Data Reader` - データ読み取り

### 3. Microsoft Entra ID

- すべてのサービスが同一テナント
- セキュリティグループ作成権限
- ユーザー・グループ管理権限

### 4. 開発環境

```bash
# REST API
curl 8.0+

# または Azure SDK (プレビュー版)
- Python: azure-search-documents >= 11.6.0b12
- .NET: Azure.Search.Documents >= 11.7.0-beta.4
- Java: azure-search-documents >= 11.8.0-beta.7
```

---

## アプローチ1: Knowledge Source（推奨・簡単）

### ステップ1: ADLS Gen2でACL設定

```bash
# Microsoft Entra IDでセキュリティグループ作成
az ad group create \
  --display-name "Sales-Team-ReadOnly" \
  --mail-nickname "sales-readonly"

# グループIDを取得
SALES_GROUP_ID=$(az ad group show \
  --group "Sales-Team-ReadOnly" \
  --query id -o tsv)

# ユーザーをグループに追加
az ad group member add \
  --group "Sales-Team-ReadOnly" \
  --member-id <user-object-id>

# ADLS Gen2にACL設定（再帰的）
az storage fs access set-recursive \
  --acl "user::rwx,group:${SALES_GROUP_ID}:r-x,other::---" \
  -p sales-documents/ \
  -f mycontainer \
  --account-name mystorageaccount \
  --auth-mode login
```

### ステップ2: Knowledge Source作成

```http
POST https://[search-service].search.windows.net/knowledgesources/my-kb?api-version=2025-11-01-preview
Content-Type: application/json
api-key: [admin-key]

{
  "name": "adls-gen2-kb",
  "kind": "azureBlob",
  "description": "ADLS Gen2 with ACL ingestion",
  "azureBlobParameters": {
    "connectionString": "[connection-string]",
    "containerName": "mycontainer",
    "folderPath": "sales-documents",
    "isADLSGen2": true,
    "ingestionParameters": {
      "embeddingModel": {
        "kind": "azureOpenAI",
        "azureOpenAIParameters": {
          "deploymentId": "text-embedding-3-large",
          "resourceUri": "https://[aoai-resource].openai.azure.com",
          "apiKey": "[aoai-key]"
        }
      },
      "ingestionPermissionOptions": [
        "userIds",
        "groupIds",
        "rbacScope"
      ],
      "disableImageVerbalization": true
    }
  }
}
```

### ステップ3: 自動生成されたオブジェクトを確認

Knowledge Source作成後、以下が**自動生成**されます：

#### 自動生成されるインデックス

```json
{
  "name": "adls-gen2-kb-index",
  "fields": [
    { "name": "id", "type": "Edm.String", "key": true },
    { "name": "content", "type": "Edm.String", "searchable": true },
    { "name": "chunk", "type": "Edm.String", "searchable": true },
    {
      "name": "vector",
      "type": "Collection(Edm.Single)",
      "vectorSearchDimensions": 3072
    },

    // ⭐ ACLフィールド（自動生成）
    {
      "name": "UserIds",
      "type": "Collection(Edm.String)",
      "permissionFilter": "userIds",
      "filterable": true,
      "retrievable": false
    },
    {
      "name": "GroupIds",
      "type": "Collection(Edm.String)",
      "permissionFilter": "groupIds",
      "filterable": true,
      "retrievable": false
    },
    {
      "name": "RbacScope",
      "type": "Edm.String",
      "permissionFilter": "rbacScope",
      "filterable": true,
      "retrievable": false
    }
  ],
  "permissionFilterOption": "enabled"
}
```

#### 自動生成されるデータソース

```json
{
  "name": "adls-gen2-kb-datasource",
  "type": "adlsgen2",
  "indexerPermissionOptions": ["userIds", "groupIds", "rbacScope"],
  "credentials": {
    "connectionString": "ResourceId=/subscriptions/..."
  }
}
```

#### 自動生成されるインデクサー

```json
{
  "name": "adls-gen2-kb-indexer",
  "dataSourceName": "adls-gen2-kb-datasource",
  "targetIndexName": "adls-gen2-kb-index",
  "fieldMappings": [
    {
      "sourceFieldName": "metadata_user_ids",
      "targetFieldName": "UserIds"
    },
    {
      "sourceFieldName": "metadata_group_ids",
      "targetFieldName": "GroupIds"
    },
    {
      "sourceFieldName": "metadata_rbac_scope",
      "targetFieldName": "RbacScope"
    }
  ]
}
```

### ステップ4: インデクサー実行確認

```http
GET https://[search-service].search.windows.net/indexers/adls-gen2-kb-indexer/status?api-version=2025-11-01-preview
api-key: [admin-key]
```

---

## アプローチ2: Indexer直接使用（高度・柔軟）

### ステップ1: データソース作成

```http
POST https://[search-service].search.windows.net/datasources?api-version=2025-11-01-preview
Content-Type: application/json
api-key: [admin-key]

{
  "name": "adls-gen2-datasource",
  "type": "adlsgen2",
  "indexerPermissionOptions": ["userIds", "groupIds", "rbacScope"],
  "credentials": {
    "connectionString": "ResourceId=/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<account-name>/;"
  },
  "container": {
    "name": "mycontainer",
    "query": "sales-documents/"
  }
}
```

**⚠️ 重要**: `indexerPermissionOptions`を指定しないと、ACLメタデータは取得されません。

### ステップ2: インデックス作成（手動定義必須）

```http
POST https://[search-service].search.windows.net/indexes?api-version=2025-11-01-preview
Content-Type: application/json
api-key: [admin-key]

{
  "name": "documents-index",
  "fields": [
    {
      "name": "id",
      "type": "Edm.String",
      "key": true,
      "filterable": true
    },
    {
      "name": "content",
      "type": "Edm.String",
      "searchable": true,
      "analyzer": "ja.microsoft"
    },
    {
      "name": "metadata_storage_path",
      "type": "Edm.String",
      "searchable": false,
      "filterable": true,
      "retrievable": true
    },
    {
      "name": "metadata_storage_name",
      "type": "Edm.String",
      "searchable": true,
      "filterable": true,
      "sortable": true
    },

    // ⚠️ 以下3つのフィールドは必須（手動定義）
    {
      "name": "UserIds",
      "type": "Collection(Edm.String)",
      "permissionFilter": "userIds",
      "filterable": true,
      "retrievable": false
    },
    {
      "name": "GroupIds",
      "type": "Collection(Edm.String)",
      "permissionFilter": "groupIds",
      "filterable": true,
      "retrievable": false
    },
    {
      "name": "RbacScope",
      "type": "Edm.String",
      "permissionFilter": "rbacScope",
      "filterable": true,
      "retrievable": false
    }
  ],
  "permissionFilterOption": "enabled"
}
```

### ステップ3: インデクサー作成（fieldMappings必須）

```http
POST https://[search-service].search.windows.net/indexers?api-version=2025-11-01-preview
Content-Type: application/json
api-key: [admin-key]

{
  "name": "documents-indexer",
  "dataSourceName": "adls-gen2-datasource",
  "targetIndexName": "documents-index",
  "schedule": {
    "interval": "PT2H"
  },
  "parameters": {
    "configuration": {
      "dataToExtract": "contentAndMetadata",
      "parsingMode": "default"
    }
  },
  "fieldMappings": [
    {
      "sourceFieldName": "metadata_storage_path",
      "targetFieldName": "metadata_storage_path"
    },
    {
      "sourceFieldName": "metadata_storage_name",
      "targetFieldName": "metadata_storage_name"
    },

    // ⚠️ ACLフィールドマッピングは必須
    {
      "sourceFieldName": "metadata_user_ids",
      "targetFieldName": "UserIds"
    },
    {
      "sourceFieldName": "metadata_group_ids",
      "targetFieldName": "GroupIds"
    },
    {
      "sourceFieldName": "metadata_rbac_scope",
      "targetFieldName": "RbacScope"
    }
  ]
}
```

### ステップ4: インデクサー実行

```http
POST https://[search-service].search.windows.net/indexers/documents-indexer/run?api-version=2025-11-01-preview
api-key: [admin-key]
```

---

## ADLS Gen2 ACL設定

### 推奨ACL構造

```bash
# ルートコンテナ（/）
user::rwx
group::r-x
other::---

# sales-documents/（営業部のみ）
user::rwx
group:aaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:r-x  # Sales-Team
other::---

# engineering-documents/（技術部のみ）
user::rwx
group:bbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb:r-x  # Engineering-Team
other::---

# public-documents/（全員）
user::rwx
group::r-x
other::r-x
```

### ACL設定のベストプラクティス

#### 1. ルートコンテナ設定

```bash
# すべてのグループに Execute 権限を付与（トラバース可能にする）
az storage fs access set \
  --permissions "user::rwx,group::r-x,other::---" \
  -p / \
  -f mycontainer \
  --account-name mystorageaccount \
  --auth-mode login

# Default ACLも設定（新規ファイル継承用）
az storage fs access set \
  --permissions "default:user::rwx,default:group::r-x,default:other::---" \
  -p / \
  -f mycontainer \
  --account-name mystorageaccount \
  --auth-mode login
```

#### 2. ディレクトリごとの設定

```bash
# 営業部ディレクトリ
az storage fs access set-recursive \
  --acl "user::rwx,group:${SALES_GROUP_ID}:r-x,other::---" \
  -p sales-documents/ \
  -f mycontainer \
  --account-name mystorageaccount \
  --auth-mode login

# Default ACLも設定
az storage fs access set \
  --acl "default:user::rwx,default:group:${SALES_GROUP_ID}:r-x,default:other::---" \
  -p sales-documents/ \
  -f mycontainer \
  --account-name mystorageaccount \
  --auth-mode login
```

#### 3. 既存permissionsの削除

```bash
# owning user, owning group, other は削除が推奨（プレビュー制限）
# 名前付きグループのみを使用
```

### Python SDKでのACL設定

```python
from azure.storage.filedatalake import DataLakeServiceClient
from azure.identity import DefaultAzureCredential

credential = DefaultAzureCredential()
service_client = DataLakeServiceClient(
    account_url="https://mystorageaccount.dfs.core.windows.net",
    credential=credential
)

filesystem_client = service_client.get_file_system_client("mycontainer")
directory_client = filesystem_client.get_directory_client("sales-documents")

# ACL設定
acl = f"user::rwx,group:{SALES_GROUP_ID}:r-x,other::---"
directory_client.set_access_control(acl=acl)

# 再帰的に適用
acl_change_result = directory_client.set_access_control_recursive(acl=acl)
print(f"Changed: {acl_change_result.counters.directories_successful + acl_change_result.counters.files_successful}")
```

---

## クエリ実行

### Python SDKでのクエリ

```python
from azure.search.documents import SearchClient
from azure.identity import DefaultAzureCredential

# 認証
credential = DefaultAzureCredential()
search_client = SearchClient(
    endpoint="https://[search-service].search.windows.net",
    index_name="documents-index",
    credential=credential
)

# ユーザートークン取得
token = credential.get_token("https://search.azure.net/.default")

# 検索実行（ACL自動適用）
results = search_client.search(
    search_text="営業戦略",
    top=10,
    additional_headers={
        "x-ms-query-source-authorization": f"Bearer {token.token}"
    }
)

# 結果表示（権限のあるドキュメントのみ）
for result in results:
    print(f"File: {result['metadata_storage_name']}")
    print(f"Score: {result['@search.score']}")
    print(f"Content: {result['content'][:200]}...")
    print("---")
```

### REST APIでのクエリ

```http
POST https://[search-service].search.windows.net/indexes/documents-index/docs/search?api-version=2025-11-01-preview
Content-Type: application/json
api-key: [query-key]
x-ms-query-source-authorization: Bearer [user-entra-id-token]

{
  "search": "営業戦略",
  "top": 10,
  "select": "metadata_storage_name,content",
  "highlight": "content",
  "queryType": "semantic",
  "semanticConfiguration": "default"
}
```

### ユーザートークンの取得（Azure CLI）

```bash
# 現在のユーザーのトークンを取得
USER_TOKEN=$(az account get-access-token \
  --resource https://search.azure.net \
  --query accessToken -o tsv)

# クエリ実行
curl -X POST \
  "https://[search-service].search.windows.net/indexes/documents-index/docs/search?api-version=2025-11-01-preview" \
  -H "Content-Type: application/json" \
  -H "api-key: [query-key]" \
  -H "x-ms-query-source-authorization: Bearer ${USER_TOKEN}" \
  -d '{
    "search": "営業戦略",
    "top": 10
  }'
```

---

## 権限同期とメンテナンス

### ACL変更時の同期方法

ADLS Gen2でACLを変更した場合、以下の方法でインデックスに反映します。

#### 1. 少数ファイルの場合（タイムスタンプ更新）

```bash
# ファイルのタイムスタンプを更新（touch）
az storage blob update \
  --container-name mycontainer \
  --name sales-documents/report.pdf \
  --account-name mystorageaccount

# 次回のインデクサー実行時に自動更新
```

#### 2. 多数ファイルの場合（resetdocs API）

```http
POST https://[search-service].search.windows.net/indexers/documents-indexer/resetdocs?api-version=2025-11-01-preview
Content-Type: application/json
api-key: [admin-key]

{
  "documentKeys": [
    "aHR0cHM6Ly9teXN0b3JhZ2UuLi4vcmVwb3J0MS5wZGY",
    "aHR0cHM6Ly9teXN0b3JhZ2UuLi4vcmVwb3J0Mi5wZGY"
  ]
}
```

#### 3. 全体同期の場合（resync API）

```http
POST https://[search-service].search.windows.net/indexers/documents-indexer/resync?api-version=2025-11-01-preview
Content-Type: application/json
api-key: [admin-key]

{
  "options": ["permissions"]
}
```

### 定期同期のスケジュール設定

```http
PUT https://[search-service].search.windows.net/indexers/documents-indexer?api-version=2025-11-01-preview
Content-Type: application/json
api-key: [admin-key]

{
  "name": "documents-indexer",
  "schedule": {
    "interval": "PT2H",
    "startTime": "2026-03-13T09:00:00Z"
  }
}
```

---

## トラブルシューティング

### 問題1: ACLメタデータが取得されない

**症状**: インデックスにUserIds/GroupIdsフィールドが空

**原因と対処**:

```bash
# 1. データソースにindexerPermissionOptionsが設定されているか確認
GET https://[search-service].search.windows.net/datasources/adls-gen2-datasource?api-version=2025-11-01-preview

# 確認項目:
# "indexerPermissionOptions": ["userIds", "groupIds", "rbacScope"]

# 2. ADLS Gen2のACLが正しく設定されているか確認
az storage fs access show \
  -p sales-documents/report.pdf \
  -f mycontainer \
  --account-name mystorageaccount \
  --auth-mode login

# 3. Search ServiceにStorage Blob Data Reader権限があるか確認
az role assignment list \
  --assignee [search-service-principal-id] \
  --scope /subscriptions/[sub-id]/resourceGroups/[rg]/providers/Microsoft.Storage/storageAccounts/[account]
```

### 問題2: ユーザーがすべてのドキュメントにアクセスできる

**症状**: ACL設定に関係なく全ドキュメントが返される

**原因と対処**:

```bash
# 1. インデックスでpermissionFilterOptionが有効か確認
GET https://[search-service].search.windows.net/indexes/documents-index?api-version=2025-11-01-preview

# 確認項目:
# "permissionFilterOption": "enabled"

# 2. クエリにユーザートークンを含めているか確認
# x-ms-query-source-authorization ヘッダーが必須

# 3. ユーザーがStorage Blob Data Ownerロールを持っていないか確認
# このロールを持つとすべてにアクセス可能
az role assignment list --assignee [user-object-id] \
  --scope /subscriptions/[sub-id]/resourceGroups/[rg]/providers/Microsoft.Storage/storageAccounts/[account]
```

### 問題3: 403 Forbidden エラー

**症状**: インデクサー実行時に403エラー

**原因と対処**:

```bash
# Search ServiceのManaged IdentityにStorage権限がない
az role assignment create \
  --role "Storage Blob Data Reader" \
  --assignee-object-id [search-service-principal-id] \
  --assignee-principal-type ServicePrincipal \
  --scope /subscriptions/[sub-id]/resourceGroups/[rg]/providers/Microsoft.Storage/storageAccounts/[account]
```

### 問題4: グループメンバーシップが反映されない

**症状**: グループに追加したユーザーがドキュメントにアクセスできない

**原因と対処**:

```bash
# 1. グループメンバーシップの確認
az ad group member list --group [group-id]

# 2. トークン再取得（キャッシュの可能性）
# ブラウザセッションをクリアまたは新しいトークンを取得

# 3. ACLがグループIDで設定されているか確認（グループ名ではダメ）
az storage fs access show \
  -p sales-documents/ \
  -f mycontainer \
  --account-name mystorageaccount \
  --auth-mode login

# 正しい形式:
# group:aaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa:r-x
```

### 問題5: パフォーマンスが遅い

**症状**: クエリ実行が遅い

**原因と対処**:

```bash
# 1. グループメンバーシップが多すぎる（推奨200未満）
# ユーザーの所属グループ数を確認
az ad user get-member-groups --id [user-object-id]

# 2. インデックスに5つ以上のrbacScopeがある（制限: 5個まで）
# rbacScopeの使用を見直す

# 3. 多数のACLエントリ（32エントリ制限）
# グループベースのACL管理に移行
```

---

## ベストプラクティス

### 1. グループベースのACL管理

```bash
# ❌ 避けるべき: 個別ユーザーへの直接割り当て
user:alice@contoso.com:r-x
user:bob@contoso.com:r-x
user:charlie@contoso.com:r-x

# ✅ 推奨: グループベースの管理
group:sales-team-id:r-x
```

**理由**:

- ユーザー追加/削除が簡単（ACL再適用不要）
- ACLエントリ数の節約
- 管理の簡素化

### 2. 階層的なACL設計

```
/mycontainer/
├── public/           # すべてに r-x
├── sales/            # Sales-Teamに r-x
│   ├── confidential/ # Sales-Managersに r-x
│   └── reports/      # Sales-Teamに r-x
└── engineering/      # Engineering-Teamに r-x
    ├── internal/     # Engineering-Teamに r-x
    └── research/     # Research-Groupに r-x
```

### 3. Default ACLの活用

```bash
# ディレクトリにDefault ACLを設定
az storage fs access set \
  --acl "default:user::rwx,default:group:${TEAM_ID}:r-x,default:other::---" \
  -p sales/ \
  -f mycontainer \
  --account-name mystorageaccount \
  --auth-mode login
```

**利点**:

- 新規ファイルが自動的に同じACLを継承
- 手動設定の手間を削減

### 4. retrievableの管理

```json
// 開発環境
{
  "name": "GroupIds",
  "type": "Collection(Edm.String)",
  "permissionFilter": "groupIds",
  "filterable": true,
  "retrievable": true  // デバッグ用
}

// 本番環境
{
  "name": "GroupIds",
  "type": "Collection(Edm.String)",
  "permissionFilter": "groupIds",
  "filterable": true,
  "retrievable": false  // セキュリティ上必須
}
```

### 5. 定期的な権限監査

```python
# 週次でACLとインデックスの整合性チェック
from azure.search.documents import SearchClient
from azure.storage.filedatalake import DataLakeServiceClient

def audit_permissions():
    # ADLS Gen2のACL取得
    storage_acls = get_storage_acls()

    # インデックスのACLメタデータ取得
    index_acls = get_index_acls()

    # 差異を検出
    discrepancies = compare_acls(storage_acls, index_acls)

    if discrepancies:
        print(f"Found {len(discrepancies)} mismatches")
        # resync API実行
        trigger_resync()
```

### 6. 最小権限の原則

```bash
# Search ServiceにはData Readerのみ（Ownerは不要）
az role assignment create \
  --role "Storage Blob Data Reader" \
  --assignee [search-principal-id]

# 開発者には必要最小限の権限
# - Search Index Data Reader (読み取り専用)
# - Search Service Contributor (管理者のみ)
```

### 7. テスト環境での検証

```bash
# 本番適用前に必ずテスト環境で検証
1. テスト用グループ作成
2. ACL設定
3. インデクサー実行
4. 複数ユーザーでクエリテスト
5. 権限変更後の同期テスト
```

### 8. ログとモニタリング

```bash
# Application Insightsの有効化
az search service update \
  --name [search-service] \
  --resource-group [rg] \
  --identity-type SystemAssigned

# インデクサー実行ログの監視
az monitor diagnostic-settings create \
  --name search-diagnostics \
  --resource [search-resource-id] \
  --logs '[{"category":"OperationLogs","enabled":true}]' \
  --workspace [log-analytics-workspace-id]
```

---

## 参考情報

### 公式ドキュメント

- [Use an ADLS Gen2 indexer to ingest permission metadata](https://learn.microsoft.com/azure/search/search-indexer-access-control-lists-and-role-based-access)
- [Document-level access control in Azure AI Search](https://learn.microsoft.com/azure/search/search-document-level-access-overview)
- [Query-time ACL and RBAC enforcement](https://learn.microsoft.com/azure/search/search-query-access-control-rbac-enforcement)
- [Access control lists (ACLs) in Azure Data Lake Storage](https://learn.microsoft.com/azure/storage/blobs/data-lake-storage-access-control)

### REST API リファレンス

- [Create or Update Index (2025-11-01-preview)](https://learn.microsoft.com/rest/api/searchservice/indexes/create-or-update?view=rest-searchservice-2025-11-01-preview)
- [Create or Update Indexer (2025-11-01-preview)](https://learn.microsoft.com/rest/api/searchservice/indexers/create-or-update?view=rest-searchservice-2025-11-01-preview)
- [Create Knowledge Source (2025-11-01-preview)](https://learn.microsoft.com/rest/api/searchservice/knowledge-sources/create?view=rest-searchservice-2025-11-01-preview)

### Azure SDK

- [Python: azure-search-documents](https://github.com/Azure/azure-sdk-for-python/tree/main/sdk/search/azure-search-documents)
- [.NET: Azure.Search.Documents](https://github.com/Azure/azure-sdk-for-net/tree/main/sdk/search/Azure.Search.Documents)
- [Java: azure-search-documents](https://github.com/Azure/azure-sdk-for-java/tree/main/sdk/search/azure-search-documents)

---

**最終更新**: 2026年3月13日  
**執筆者**: AI Assistant  
**バージョン**: 1.0

# トラブルシューティング

## admin権限(検索インデックス共同作成者割り当てていること)で確認

```bash
ACCESS_TOKEN=$(az account get-access-token --resource https://search.azure.com --query accessToken -o tsv) &&  curl -X POST    "https://testaif.search.windows.net/indexes/index-acl/docs/search?api-version=2025-11-01-preview"    -H "Authorization: Bearer $ACCESS_TOKEN"    -H "x-ms-enable-elevated-read: true"    -H "Content-Type: application/json"    -d '{
     "search": "*",
     "top": 3,
     "count": true
   }'
```

- ユーザーやグループID反映確認

```bash
echo "=== 20秒追加で待機 ===" && \
sleep 20 && \
ACCESS_TOKEN=$(az account get-access-token --resource https://search.azure.com --query accessToken -o tsv) && \
echo "=== UserIdsフィールドを確認（サンプル3件） ===" && \
curl -X POST \
  "https://testaif.search.windows.net/indexes/index-acl/docs/search?api-version=2025-11-01-preview" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-ms-enable-elevated-read: true" \
  -H "Content-Type: application/json" \
  -d '{
    "search": "*",
    "top": 3
  }' | jq '.value[0:3] | map({
    title: .title,
    UserIds: .UserIds,
    GroupIds: .GroupIds
  })'
```

## acl更新後の適用

```bash
ACCESS_TOKEN=$(az account get-access-token --resource https://search.azure.com --query accessToken -o tsv) && \
echo "=== ステップ1: Resync API（permissionsモード設定） ===" && \
curl -X POST \
  "https://testaif.search.windows.net/indexers/indexer-acl/resync?api-version=2025-11-01-preview" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"options": ["permissions"]}' && \
echo -e "\n\n=== ステップ2: インデクサー実行（1回目 - Resyncモード） ===" && \
curl -X POST \
  "https://testaif.search.windows.net/indexers/indexer-acl/run?api-version=2025-11-01-preview" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Length: 0" && \
echo -e "\n\n30秒待機中..." && \
sleep 30 && \
echo "=== ステップ3: インデクサー実行（2回目 - 通常モード） ===" && \
curl -X POST \
  "https://testaif.search.windows.net/indexers/indexer-acl/run?api-version=2025-11-01-preview" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Length: 0" && \
echo -e "\n\n10秒待機後、ステータス確認..." && \
sleep 10 && \
curl -X GET \
  "https://testaif.search.windows.net/indexers/indexer-acl/status?api-version=2025-11-01-preview" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq '{
    status: .status,
    lastResult: {
      status: .lastResult.status,
      itemsProcessed: .lastResult.itemsProcessed,
      itemsFailed: .lastResult.itemsFailed
    }
  }'
```

- ユーザーやグループID反映確認

```bash
echo "=== 20秒追加で待機 ===" && \
sleep 20 && \
ACCESS_TOKEN=$(az account get-access-token --resource https://search.azure.com --query accessToken -o tsv) && \
echo "=== UserIdsフィールドを確認（サンプル3件） ===" && \
curl -X POST \
  "https://testaif.search.windows.net/indexes/index-acl/docs/search?api-version=2025-11-01-preview" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-ms-enable-elevated-read: true" \
  -H "Content-Type: application/json" \
  -d '{
    "search": "*",
    "top": 3
  }' | jq '.value[0:3] | map({
    title: .title,
    UserIds: .UserIds,
    GroupIds: .GroupIds
  })'
```

## gen aclの注意事項

コンテナに設定と各配下のディレクトリに再帰的に適用が必要

```bash
# 例
# ステップ1: ルートコンテナ（Access ACLのみ、Default ACLなし）
## コンテナ配下に適用するグループ及びユーザーのオブジェクトIDに対するaclはすべてルートでも設定する
az storage fs access set \
  --acl "user::rwx,user:<objectid>:r-x,group::r-x,other::---" \
  -p / \
  -f ais-docs \
  --account-name testst \
  --auth-mode login

# ステップ2: Tartarian/ディレクトリ（Access ACL + Default ACL、再帰的適用）
az storage fs access set-recursive \
  --acl "user::rwx,user:<objectid>:r-x,group::r-x,other::---,default:user::rwx,default:user:<objectid>:r-x,default:group::r-x,default:other::---" \
  -p Tartarian/ \
  -f ais-docs \
  --account-name testst \
  --auth-mode login
```
