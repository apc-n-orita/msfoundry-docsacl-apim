# Azure AI Search × Microsoft Purview 機密度ラベル連携ガイド

> **ステータス**: パブリックプレビュー（2025-11-01-preview API）  
> **参考**: [公式ドキュメント](https://learn.microsoft.com/azure/search/search-indexer-sensitivity-labels)

## 概要

Azure AI Search は、インデックス作成時に Microsoft Purview の機密度ラベルを自動抽出し、クエリ時にラベルベースのドキュメントレベルアクセス制御を適用する機能を提供する。  
これにより、Microsoft Purview で定義された情報保護ポリシーを検索・RAG アプリケーションに適用できる。

### 動作の流れ

1. **インデックス作成時**: インデクサーがデータソースからドキュメントと機密度ラベルメタデータを抽出・格納
2. **クエリ時**: ユーザーの Entra トークンとラベルポリシーを照合し、READ 使用権を持つドキュメントのみ返却

## 対応データソース

- Azure Blob Storage
- Azure Data Lake Storage Gen2
- SharePoint in Microsoft 365（プレビュー）
- Microsoft OneLake

## 前提条件

- Microsoft Purview 機密度ラベルポリシーが構成済みで、ドキュメントに適用済み
- グローバル管理者 または 特権ロール管理者 のロール（権限付与に必要）
- AI Search サービスとクエリユーザーが同一 Microsoft Entra テナント内
- REST API バージョン `2025-11-01-preview` 以降

## 制限事項

- Azure ポータル非対応（REST API / SDK のみ）
- Autocomplete / Suggest API は非対応
- ゲストアカウント・クロステナントクエリ非対応
- 以下のインデクサー機能はラベル付きドキュメントに非対応:
  - Custom Web API スキル
  - GenAI Prompt スキル
  - ナレッジストア
  - インデクサーエンリッチメントキャッシュ
  - デバッグセッション

---

## 設定手順

### 手順 1: AI Search マネージド ID を有効化

AI Search サービスの **システム割り当てマネージド ID** を有効化する。  
インデクサーが Purview に安全にアクセスしてラベルメタデータを抽出するために必要。

### 手順 2: AI Search の RBAC を有効化

ロールベースアクセス制御（RBAC）を有効にする。  
既存 API キーとの併用可（運用への影響を避けるため推奨）。

### 手順 3: Purview へのアクセス権限を付与

グローバル管理者が、AI Search のマネージド ID に以下のロールを付与する：

| ロール                        | 用途                                        |
| ----------------------------- | ------------------------------------------- |
| **Content.SuperUser**         | ラベルとコンテンツの抽出                    |
| **UnifiedPolicy.Tenant.Read** | Purview ポリシー/ラベルメタデータの読み取り |

#### PowerShell スクリプト

```powershell
Install-Module -Name Az -Scope CurrentUser
Install-Module -Name Microsoft.Entra -AllowClobber
Import-Module Az.Resources
Connect-Entra -Scopes 'Application.ReadWrite.All'

$resourceIdWithManagedIdentity = "subscriptions/<subscriptionId>/resourceGroups/<resourceGroup>/providers/Microsoft.Search/searchServices/<searchServiceName>"
$managedIdentityObjectId = (Get-AzResource -ResourceId $resourceIdWithManagedIdentity).Identity.PrincipalId

# Microsoft Information Protection (MIP) - Content.SuperUser
$MIPResourceSP = Get-EntraServicePrincipal -Filter "appID eq '870c4f2e-85b6-4d43-bdda-6ed9a579b725'"
New-EntraServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentityObjectId -Principal $managedIdentityObjectId -ResourceId $MIPResourceSP.Id -Id "8b2071cd-015a-4025-8052-1c0dba2d3f64"

# ARM Service Principal - UnifiedPolicy.Tenant.Read
$ARMSResourceSP = Get-EntraServicePrincipal -Filter "appID eq '00000012-0000-0000-c000-000000000000'"
New-EntraServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentityObjectId -Principal $managedIdentityObjectId -ResourceId $ARMSResourceSP.Id -Id "7347eb49-7a1a-43c5-8eac-a5cd1d1c7cf0"
```

| AppID                                  | サービスプリンシパル                   |
| -------------------------------------- | -------------------------------------- |
| `870c4f2e-85b6-4d43-bdda-6ed9a579b725` | Microsoft Info Protection Sync Service |
| `00000012-0000-0000-c000-000000000000` | Azure Resource Manager                 |

### 手順 4: インデックスに Purview を有効化

インデックス作成時に `purviewEnabled: true` を設定する。

> **重要**: この設定は作成後の変更不可。RBAC 認証のみサポート（API キーはスキーマ取得のみ）。

```json
PUT https://{service}.search.windows.net/indexes('{indexName}')?api-version=2025-11-01-preview
{
  "purviewEnabled": true,
  "fields": [
    {
      "name": "sensitivityLabel",
      "type": "Edm.String",
      "filterable": true,
      "sensitivityLabel": true,
      "retrievable": true
    }
  ]
}
```

### 手順 5: データソースの構成

`indexerPermissionOptions` を `["sensitivityLabel"]` に設定する。

```json
{
  "name": "purview-sensitivity-datasource",
  "type": "azureblob",
  "indexerPermissionOptions": ["sensitivityLabel"],
  "credentials": {
    "connectionString": "<your-connection-string>"
  },
  "container": {
    "name": "<container-name>"
  }
}
```

> `type` はデータソースに応じて `sharepoint`, `onelake`, `adlsgen2` に変更。

### 手順 6: （オプション）スキルセットのインデックスプロジェクション

**テキスト分割（チャンキング）を使う場合のみ必要。** 親ドキュメントのラベルを各チャンクに引き継ぐための設定。

```json
PUT https://{service}.search.windows.net/skillsets/{skillset}?api-version=2025-11-01-preview
{
  "name": "my-skillset",
  "skills": [
    {
      "@odata.type": "#Microsoft.Skills.Text.SplitSkill",
      "name": "#split",
      "context": "/document",
      "inputs": [{ "name": "text", "source": "/document/content" }],
      "outputs": [{ "name": "textItems", "targetName": "chunks" }]
    }
  ],
  "indexProjections": {
    "selectors": [
      {
        "targetIndexName": "chunks-index",
        "parentKeyFieldName": "parentId",
        "sourceContext": "/document/chunks/*",
        "mappings": [
          { "name": "content", "source": "/document/chunks/*/text" },
          { "name": "parentId", "source": "/document/id" },
          { "name": "sensitivityLabel", "source": "/document/metadata_sensitivity_label" }
        ]
      }
    ],
    "parameters": {
      "projectionMode": "skipIndexingParentDocuments"
    }
  }
}
```

| 要素                        | 説明                                                               |
| --------------------------- | ------------------------------------------------------------------ |
| `targetIndexName`           | チャンクを格納するインデックス名                                   |
| `parentKeyFieldName`        | 親ドキュメントキーのフィールド名                                   |
| `sourceContext`             | チャンキング出力パス（Split スキルの出力に合わせる）               |
| `mappings.sensitivityLabel` | **親ドキュメントからラベルをチャンクにマッピング（必須）**         |
| `projectionMode`            | `skipIndexingParentDocuments` でチャンクのみインデックス化（推奨） |

> マッピングしないとチャンクにラベルが引き継がれず、クエリ時のアクセス制御が機能しない。

### 手順 7: インデクサーの構成

フィールドマッピングでラベルメタデータをインデックスフィールドにルーティングし、スケジュール実行を設定。

```json
{
  "fieldMappings": [
    {
      "sourceFieldName": "metadata_sensitivity_label",
      "targetFieldName": "sensitivityLabel"
    }
  ]
}
```

最小スケジュール間隔: 5分

### 手順 8: クエリ時のアクセス制御

クエリリクエストに `x-ms-query-source-authorization` ヘッダーでユーザーの Entra トークンを付与する。

```http
POST /indexes/sensitivity-docs/docs/search?api-version=2025-11-01-preview
Authorization: Bearer {{app-query-token}}
x-ms-query-source-authorization: Bearer {{user-query-token}}
Content-Type: application/json

{
    "search": "*",
    "select": "title,summary,sensitivityLabel",
    "orderby": "title asc"
}
```

---

## Foundry IQ との連携

Foundry IQ は Azure AI Search をナレッジ検索基盤として使用するため、**AI Search 側で Purview 機密度ラベルを有効化すれば自動的に連携される。**

### ナレッジソース別の対応

| ナレッジソース                                 | Purview 機密度ラベル対応方法                                                                      |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| **インデックス型**（Blob, ADLS Gen2, OneLake） | AI Search インデクサーでラベルを取り込み、クエリ時に適用（上記手順 1〜8）                         |
| **リモート SharePoint**                        | Copilot Retrieval API 経由で ACL + Purview ラベルを Out-of-the-box 適用（Copilot ライセンス必要） |

### 現在のコードとの関係

`foudryIQ_agent/acl_on/main.py` では既に MCP ツール呼び出し時に `x-ms-query-source-authorization` ヘッダーでユーザートークンを渡している：

```python
mcp_tool = {
    "type": "mcp",
    "server_label": "kb_acl_test",
    "server_url": kb_mcp_url,
    "headers": {"x-ms-query-source-authorization": user_token},
}
```

→ **AI Search 側で Purview 機密度ラベルを有効化すれば、コード変更なしで連携可能。**

### 注意事項

- 暗号化されたアイテムの場合、ユーザーは **EXTRACT** 使用権（および VIEW）が必要
- Foundry IQ のナレッジソースと Copilot のナレッジソースは互換性がない（相互利用不可）
- リモート SharePoint ソースには有効な Copilot ライセンスが必要

---

## UI でのラベル表示

クエリ結果には機密度ラベルの **GUID** のみが返却される。ラベル名やポリシー設定をアプリ UI に表示するには、Microsoft Purview Information Protection エンドポイント（Graph API）を呼び出す必要がある。

### 使用可能な Graph API

| API                                                                                                                     | 用途                    |
| ----------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| [List sensitivity labels](https://learn.microsoft.com/graph/api/tenantdatasecurityandgovernance-list-sensitivitylabels) | ラベル一覧取得          |
| [Get sensitivity label](https://learn.microsoft.com/graph/api/sensitivitylabel-get)                                     | GUID からラベル詳細取得 |
| [List usage rights](https://learn.microsoft.com/graph/api/usagerightsincluded-get)                                      | 使用権一覧取得          |
| [Compute inheritance](https://learn.microsoft.com/graph/api/sensitivitylabel-computeinheritance)                        | ラベル継承の計算        |
| [Compute rights and inheritance](https://learn.microsoft.com/graph/api/sensitivitylabel-computerightsandinheritance)    | 権限と継承の計算        |

---

## 参考リンク

- [Azure AI Search - Purview 機密度ラベル連携](https://learn.microsoft.com/azure/search/search-indexer-sensitivity-labels)
- [クエリ時の機密度ラベル適用](https://learn.microsoft.com/azure/search/search-query-sensitivity-labels)
- [ドキュメントレベルアクセス制御の概要](https://learn.microsoft.com/azure/search/search-document-level-access-overview)
- [Foundry IQ とは](https://learn.microsoft.com/azure/foundry/agents/concepts/what-is-foundry-iq)
- [Foundry IQ FAQ - セキュリティとガバナンス](https://learn.microsoft.com/azure/foundry/agents/concepts/foundry-iq-faq)
- [Purview × Microsoft Foundry 連携](https://learn.microsoft.com/purview/ai-azure-foundry)
- [インデックスプロジェクション定義](https://learn.microsoft.com/azure/search/search-how-to-define-index-projections)
