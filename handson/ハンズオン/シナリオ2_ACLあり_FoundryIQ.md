# シナリオ 2: ACL あり — Foundry IQ Knowledge Agent 直接呼び出し

## ⚠️ 注意: 現在エラーが発生しています

ADLS Gen2 ACL による検索フィルタリング (`x-ms-query-source-authorization`) とハイブリッド検索（セマンティック＋ベクトル）を同時に使用すると、以下のエラーが発生し現時点ではハンズオンを完遂できません。

```json
{
  "error": {
    "code": "",
    "message": "Unable to complete search request successfully"
  }
}
```

原因と対策を調査中です。このシナリオはアーキテクチャの理解を目的として参照し、実際の動作確認は[シナリオ 3](./シナリオ3_ACLあり_クラシックRAG.md) で行ってください。

---

## 概要

OBO (On-Behalf-Of) フローでユーザートークンを取得し、MCP リクエストの `x-ms-query-source-authorization` ヘッダーに付与します。
Azure AI Search が JWT 内のグループ情報をもとにドキュメントをフィルタリングするため、ユーザーが所属するグループが ACL に含まれるドキュメントのみ参照できます。

**使用コード**: `appcodes/acl_on/`

---

## 処理フロー

```
クライアント (acl_on/main.py)
  │
  │  [1] DefaultAzureCredential でアプリスコープのトークンを取得
  │        api://<client_id>/.default
  │
  │  [2] MSAL OBO フロー: AI Search 用トークンに交換
  │        acquire_token_on_behalf_of()
  │        scope: https://search.azure.com/user_impersonation
  │
  ▼
Azure API Management
  │
  ▼
AI Foundry Project エンドポイント
  │  responses.create(
  │    model=model_deployment,
  │    tools=[{
  │      type: "mcp",
  │      server_url: kb_acl_mcp_url,          ← Foundry IQ MCP サーバー URL
  │      project_connection_id: "foundryIQ-docsacl",
  │      headers: {
  │        "x-ms-query-source-authorization": user_token  ← OBO トークン
  │      }
  │    }]
  │  )
  ▼
Foundry IQ (foundryIQ-docsacl 接続)
  │
  ▼
kb-tartalia-acl-gen2 (ナレッジベース)
  │  user_token のグループで GroupIds フィールドをフィルタリング
  │  → ユーザーが所属するグループのドキュメントのみ返却
  ▼
LLM が回答を生成して返却
```

---

## 環境変数

| 変数名                        | 説明                                    | 例                                                                                                        |
| ----------------------------- | --------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `PROJECT_ENDPOINT`            | AI Foundry Project のエンドポイント URL | `https://<foundry>.services.ai.azure.com/api/projects/aiproject`                                          |
| `MODEL_DEPLOYMENT`            | チャットモデルのデプロイ名              | `gpt-4o`                                                                                                  |
| `KB_ACL_MCP_URL`              | Knowledge Base MCP サーバー URL         | `https://<ais>.search.windows.net/knowledgebases/kb-tartalia-acl-gen2/mcp?api-version=2025-11-01-Preview` |
| `PROJECT_AIS_CONNECTION_NAME` | Foundry IQ への接続名                   | `foundryIQ-docsacl`                                                                                       |
| `AZURE_OBO_CLIENT_ID`         | Entra ID アプリの Client ID             | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`                                                                    |
| `AZURE_OBO_CLIENT_SECRET`     | Entra ID アプリの Client Secret         | (環境構築で発行したシークレット)                                                                          |
| `AZURE_OBO_TENANT_ID`         | テナント ID                             | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`                                                                    |
| `OTEL_SERVICE_NAME`           | OpenTelemetry サービス名                | `scenario2-acl-on`                                                                                        |

---

## 手順

### Step 1: 環境変数を設定する

```bash
export PROJECT_ENDPOINT="$(azd env get-value PROJECT_ENDPOINT)"
export MODEL_DEPLOYMENT="$(azd env get-value MODEL_DEPLOYMENT)"
export KB_ACL_MCP_URL="$(azd env get-value KB_ACL_MCP_URL)"
export PROJECT_AIS_CONNECTION_NAME="foundryIQ-docsacl"
export AZURE_OBO_CLIENT_ID="$(azd env get-value AZURE_OBO_CLIENT_ID)"
export AZURE_OBO_CLIENT_SECRET="$(az ad app credential reset --id "$AZURE_OBO_CLIENT_ID" --years 1 --append --query "password" -o tsv)"
export AZURE_OBO_TENANT_ID="$(azd env get-value AZURE_TENANT_ID)"
export OTEL_SERVICE_NAME="scenario2-acl-on"
```

### Step 2: アプリを実行する

```bash
cd appcodes
source .venv/bin/activate  # Windows: .venv\Scripts\activate
python acl_on/main.py
```

起動時に OBO フローが実行されます。

```
Azure AI Search 用トークン取得中（OBOフロー）...
=== MS foundry 接続情報 ===
Project: https://...
...
```

### Step 3: 質問を入力して ACL の動作を確認する

```
ユーザー: タルタリアとはどんな文明ですか？
```

コンソールに以下が出力されることを確認します。

- `[DEBUG] Cookie未設定（初回リクエスト）` — 初回リクエスト
- `Response ID` — 次ターンで使用
- ACL ありのナレッジベースから取得した情報を元にした回答

### Step 4: ACL の効果を確認する

現在ログインしているユーザーは `adls-acl-group` に所属しているため、`Tartarian/` ディレクトリのドキュメントが参照できます。

> **補足**: ACL が機能する仕組みは以下の通りです。
>
> 1. ADLS Gen2 のルートコンテナに `adls-acl-group` の通過権限 (`--x`) が、`Tartarian/*` ディレクトリ配下は再帰的に読み取り権限 (`r-x`) が付与されている
> 2. AI Search インデクサーがこの ADLS Gen2 の ACL 情報を `GroupIds` フィールドとしてインデックスに格納する
> 3. リクエスト時に OBO トークンをヘッダーに付与することで、AI Search がトークン内のグループ ID と `GroupIds` を照合し、一致したドキュメントのみ返す

### Step 5: シナリオ 1 との比較

同じ質問をシナリオ 1 と 2 で試すと、以下の違いが見えます。

| 観点             | シナリオ 1 (acl_off)     | シナリオ 2 (acl_on)               |
| ---------------- | ------------------------ | --------------------------------- |
| ナレッジベース   | `kb-tartalia-noacl-gen2` | `kb-tartalia-acl-gen2`            |
| ドキュメント取得 | 全件                     | グループ一致のみ                  |
| ヘッダー         | なし                     | `x-ms-query-source-authorization` |

### Step 6: Application Insights でトレースを確認する

確認手順は[シナリオ 1 の Step 5](./シナリオ1_ACLなし.md#step-5-application-insights-でトレースを確認する) と同様です。

> **注意**: Foundry ポータルではシナリオ 2 のトレースは閲覧できません。Application Insights のみで確認してください。

シナリオ 2 の `user_chat_turn` スパンには以下のカスタム属性が記録されます。

| 属性名                    | 内容                         |
| ------------------------- | ---------------------------- |
| `model_deployment`        | 使用するモデルのデプロイ名   |
| `gen_ai.prompt`           | ユーザーの入力テキスト       |
| `tokens.input`            | 入力トークン数               |
| `tokens.output`           | 出力トークン数               |
| `tokens.total`            | 合計トークン数               |
| `tokens.input.cached`     | キャッシュ済み入力トークン数 |
| `tokens.output.reasoning` | 推論トークン数               |

### Step 7: 終了する

```
ユーザー: exit
```

---

## コード解説

### `acl_on/modules/auth_utils.py` — OBO フロー

```python
def exchange_token_for_search(user_assertion, client_id, client_secret, tenant_id):
    """On-Behalf-OfフローでAzure AI Search用トークンに交換"""
    app = msal.ConfidentialClientApplication(
        client_id=client_id,
        client_credential=client_secret,
        authority=f"https://login.microsoftonline.com/{tenant_id}"
    )
    result = app.acquire_token_on_behalf_of(
        user_assertion=user_assertion,
        scopes=["https://search.azure.com/user_impersonation"]
    )
    return result["access_token"]
```

- `user_assertion`: `DefaultAzureCredential` で取得したアプリスコープのトークン
- `acquire_token_on_behalf_of()`: ユーザーの代理として AI Search 用トークンに交換する MSAL の OBO フロー

### `acl_on/modules/response_api.py` — MCP ツール定義

```python
mcp_tool = {
    "type": "mcp",
    "server_label": "kb_acl_test",
    "server_url": kb_acl_mcp_url,
    "project_connection_id": project_connection_id,  # "foundryIQ-docsacl"
    "require_approval": "never",
    "allowed_tools": ["knowledge_base_retrieve"],
    "headers": {
        "x-ms-query-source-authorization": user_token  # OBO トークン
    },
}

response = openai_client.responses.create(
    model=model_deployment,
    input=user_input,
    tools=[mcp_tool],
    previous_response_id=previous_response_id
)
```

- `x-ms-query-source-authorization` ヘッダーに OBO トークンを付与することで、AI Search 側でユーザーのグループに基づいたフィルタリングが行われます

## 次のシナリオ

OBO フローと Azure AI Search を直接組み合わせるクラシック RAG パターンは、[シナリオ 3](./シナリオ3_ACLあり_クラシックRAG.md) で体験できます。

---

## 前のシナリオ

- [シナリオ 1 — ACL なし](./シナリオ1_ACLなし.md)
