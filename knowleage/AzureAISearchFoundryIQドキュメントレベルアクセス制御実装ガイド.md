これまでの対話をすべて統合し、Azure AI Search と Foundry IQ（Azure AI Foundry）の連携におけるドキュメントレベルアクセス制御の実装ガイドとしてマークダウン形式でまとめました。

---

# Azure AI Search × Foundry IQ ドキュメントレベルアクセス制御 実装ガイド

## 1. 構成の概要

Azure AI Foundry の `responses` API (Chat Completion API) を使用して、バックエンドの Azure AI Search（Foundry IQ）に格納されたデータに対し、ユーザーごとの権限に基づいたフィルタリング（セキュリティトリミング）を適用します。

### 連携の仕組み

* **Foundry IQ:** Azure AI Search を「ベクトルストア（Vector Store）」として抽象化して利用します。
* **ドキュメントレベルセキュリティ:** 検索クエリ時にユーザーの Entra ID トークンを伝播させ、ドキュメントに付随する ACL（アクセス制御リスト）と照合します。

---

## 2. 実装コード (Python)

`openai_client.responses.create` を使用する場合の具体的な実装例です。`extra_headers` を利用して認証情報を渡すのが最大のリニエーションです。

```python
import os
from azure.identity import DefaultAzureCredential
from openai import AzureOpenAI

# 1. クライアントの初期化
credential = DefaultAzureCredential()
openai_client = AzureOpenAI(
    azure_endpoint=os.getenv("PROJECT_ENDPOINT"),
    azure_ad_token_provider=get_bearer_token_provider(credential, "https://ai.azure.com/.default"),
    api_version="2025-11-15-preview"
)

# 2. ユーザーの代理として AI Search 用のトークンを取得
# このトークンがドキュメントの閲覧権限を判定するために使用されます
search_scope = "https://search.azure.com/.default"
user_search_token = credential.get_token(search_scope).token

# 3. リクエストの実行
request_body = {
    "agent": {
        "name": os.getenv("AGENT_NAME"),
        "type": "agent_reference"
    }
}

response = openai_client.responses.create(
    input="機密情報を含む質問内容",
    extra_body=request_body,
    # 重要: ヘッダーにトークンをセット
    extra_headers={
        "x-ms-query-source-authorization": f"Bearer {user_search_token}"
    }
)

print(response.output_text)

```

---

## 3. データソースごとの対応

ドキュメントレベルのアクセス制御は、データソースによって ACL 情報の取り扱いが異なります。

| データソース | 制御の仕組み | 実装のポイント |
| --- | --- | --- |
| **SharePoint** | 自動連携 | インデクサーが ACL を自動抽出。標準機能で最も容易に連携可能。 |
| **ADLS Gen2** | ACL 抽出 | 階層型名前空間が有効な場合、POSIX ACL をメタデータとして抽出可能。 |
| **Blob Storage** | カスタムメタデータ | Blob のメタデータに許可ユーザー/グループの **GUID** を書き込み、インデックスの `Collection(Edm.String)` フィールドにマッピングする。 |

---

## 4. 重要な前提条件と注意点

### 権限設定 (RBAC)

* 検索サービス側で「Microsoft Entra ID 認証」が有効であること。
* 実行ユーザーまたはマネージド ID に **「検索インデックス データ閲覧者」** ロールが割り当てられていること。

### インデックスの構成

* インデックス側で、セキュリティフィルタ用のフィールド（例: `group_ids`, `user_ids`）が `filterable: true` で定義されている必要があります。

### 用語の定義

* **Vector Store (ベクトルストア):** Foundry UI 上での呼称。実体は Azure AI Search の「検索インデックス」です。
* **agent_reference:** `responses` API で、Foundry IQ に紐付けられたナレッジを検索対象にするための指定方法です。

---

## 5. まとめ

Foundry IQ と連携する場合、`request_body` にフィルタ句を書き込むのではなく、**`x-ms-query-source-authorization` ヘッダーにユーザーのトークンを含める**のが、セキュリティと運用性を両立した推奨手法となります。

---

**次にお手伝いできること：**
このガイドに基づいた、実際のインデクサー（特に Blob Storage 向け）の JSON 定義ファイルのサンプルが必要な場合はお知らせください。
