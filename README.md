# APIMを介したFoundry IQのナレッジエージェントハンズオン

Azure API Management (APIM) をゲートウェイとして、Azure AI Foundry IQ の Knowledge Base に接続するナレッジエージェントを構築するハンズオンです。
ドキュメントレベルのアクセス制御 (ACL) を Azure Data Lake Storage Gen2 と Azure AI Search の組み合わせで実現し、ユーザーごとに参照できるドキュメントを制限する仕組みを体験します。

---

## アーキテクチャ概要

```
クライアント (Python)
    │
    │  Azure AD / OBO フロー (ACL 有効時)
    ▼
Azure API Management (BasicV2)
    │  ルーティング / レート制限 / 認証
    ├──→ Foundry Agent API  ──→ AI Foundry Project
    ├──→ OpenAI API         ──→ AI Foundry (Azure OpenAI)
    └──→ Cognitive Services ──→ AI Foundry (埋め込みモデル)
                                    │
                            Foundry IQ (MCP サーバー)
                                    │
                            Azure AI Search
                            ナレッジベース
                            (kb-tartalia-*-gen2)
                                    │
                            ADLS Gen2 (ドキュメント)
                            Tartarian/ ディレクトリ
                            ACL によるアクセス制御
```

---

## 構成リソース

`infra/main.tf` で定義されているリソースは以下の通りです。

| リソース | 種別 | 説明 |
|---|---|---|
| Azure Resource Group | `azurerm_resource_group` | 全リソースのコンテナ |
| Azure AI Foundry | `Microsoft.CognitiveServices/accounts` | LLM / 埋め込みモデルのホスト |
| AI Foundry Project | `Microsoft.CognitiveServices/accounts/projects` | エージェント実行環境 |
| Azure AI Search | `azurerm_search_service` (Basic) | ベクトル検索 + セマンティック検索 + ACL |
| Azure Storage (ADLS Gen2) | `azurerm_storage_account` | ドキュメント格納 (ACL 付き) |
| Azure API Management | `azurerm_api_management` (BasicV2) | ゲートウェイ |
| Application Insights | `azurerm_application_insights` | 分散トレース |
| Log Analytics Workspace | `azurerm_log_analytics_workspace` | ログ集約 |
| Entra ID アプリ登録 | `azuread_application` | OBO フロー用 OAuth アプリ |
| Entra ID グループ | `azuread_group` | ADLS ACL 管理用グループ |

### APIM に登録される API

| API モジュール | パス | 用途 |
|---|---|---|
| `apim-api/foundry-agent` | Foundry Agent API | エージェント呼び出し |
| `apim-api/openai` | OpenAI 互換 API | チャット / 補完 |
| `apim-api/cognitiveservices` | Cognitive Services API | 埋め込み生成 |

### Foundry IQ 接続 (Knowledge Base MCP)

AI Foundry Project には 2 つのナレッジベース接続が作成されます。

| 接続名 | ナレッジベース | ACL |
|---|---|---|
| `foundryIQ` | `kb-tartalia-noacl-gen2` | なし (全ユーザー参照可) |
| `foundryIQ-docsacl` | `kb-tartalia-acl-gen2` | あり (グループによる制御) |

### Foundry エージェント

`null_resource.foundry_agent` にてデプロイされるエージェント:

- **エージェント名**: `info-agent-tartaria`
- **モデル**: `var.openai_chat.model_name` で指定
- **ツール**: `foundryIQ` 接続経由で `knowledge_base_retrieve` を呼び出す MCP ツール
- **指示**: ナレッジまたはツールからのみ情報を取得し、都市伝説的要素を含む場合は判断をユーザーに委ねる

---

## ACL の仕組み

```
ADLS Gen2 (ais-docs コンテナ)
└── Tartarian/
    └── *.pdf / *.txt  ← ドキュメント

ADLS ACL:
  - ルート: group (adls-acl-group) = --x  (ディレクトリのトラバースのみ)
  - Tartarian/: group (adls-acl-group) = r-x  (読み取り可)

AI Search インデクサー:
  - ADLS のグループ ACL を読み取り、GroupIds フィールドとしてインデックスに格納

ユーザー認証 (OBO フロー):
  1. クライアントが Entra ID の oauth-app トークンを取得
  2. MSAL の acquire_token_on_behalf_of() で AI Search 用トークンに交換
  3. x-ms-query-source-authorization ヘッダーにユーザートークンを付与
  4. AI Search が JWT のグループ情報でドキュメントをフィルタリング
```

---

## ハンズオンシナリオ

`appcodes/` 配下に 3 つのシナリオが用意されています。

### シナリオ 1: ACL なし — Foundry Agent 経由 (`acl_off/`)

Foundry Project に事前デプロイされたエージェントをシンプルに呼び出します。OBO フローは不要です。

**必要な環境変数**

| 変数名 | 説明 |
|---|---|
| `PROJECT_ENDPOINT` | AI Foundry Project のエンドポイント URL |
| `AGENT_NAME` | 呼び出すエージェント名 (`info-agent-tartaria`) |
| `OTEL_SERVICE_NAME` | OpenTelemetry サービス名 |

**実行**

```bash
cd appcodes
pip install -r requirements.txt
export PROJECT_ENDPOINT="https://<foundry>.services.ai.azure.com/api/projects/aiproject"
export AGENT_NAME="info-agent-tartaria"
export OTEL_SERVICE_NAME="acl-off-demo"
python acl_off/main.py
```

**処理フロー**

```
main.py
  ├── AIProjectClient で Application Insights 接続情報を取得
  ├── OpenTelemetry でトレースを設定
  ├── AzureOpenAI クライアントを生成 (ai.azure.com エンドポイント)
  └── run_chat_loop()
        └── responses.create(model=agent_name, input=user_input)
              → Foundry Agent が MCP 経由でナレッジを検索
              → 回答を返却
```

---

### シナリオ 2: ACL あり — Foundry IQ Knowledge Agent 直接呼び出し (`acl_on/`)

OBO フローでユーザートークンを取得し、MCP リクエストの `x-ms-query-source-authorization` ヘッダーに付与することで、ユーザーのグループに応じたドキュメントのみ参照させます。

**必要な環境変数**

| 変数名 | 説明 |
|---|---|
| `PROJECT_ENDPOINT` | AI Foundry Project のエンドポイント URL |
| `MODEL_DEPLOYMENT` | チャットモデルのデプロイ名 |
| `KB_MCP_URL` | Knowledge Base MCP サーバー URL (`https://<ais>.search.windows.net/knowledgebases/kb-tartalia-acl-gen2/mcp?api-version=2025-11-01-Preview`) |
| `PROJECT_AIS_CONNECTION_NAME` | Foundry IQ への接続名 (`foundryIQ-docsacl`) |
| `AZURE_OBO_CLIENT_ID` | Entra ID アプリの Client ID |
| `AZURE_OBO_CLIENT_SECRET` | Entra ID アプリの Client Secret |
| `AZURE_OBO_TENANT_ID` | テナント ID |
| `OTEL_SERVICE_NAME` | OpenTelemetry サービス名 |

**実行**

```bash
export PROJECT_ENDPOINT="https://<foundry>.services.ai.azure.com/api/projects/aiproject"
export MODEL_DEPLOYMENT="gpt-4o"
export KB_MCP_URL="https://<ais>.search.windows.net/knowledgebases/kb-tartalia-acl-gen2/mcp?api-version=2025-11-01-Preview"
export PROJECT_AIS_CONNECTION_NAME="foundryIQ-docsacl"
export AZURE_OBO_CLIENT_ID="<client_id>"
export AZURE_OBO_CLIENT_SECRET="<client_secret>"
export AZURE_OBO_TENANT_ID="<tenant_id>"
export OTEL_SERVICE_NAME="acl-on-demo"
python acl_on/main.py
```

**処理フロー**

```
main.py
  ├── AIProjectClient で Application Insights 接続情報を取得
  ├── OpenTelemetry でトレースを設定
  ├── OBO フロー
  │     └── exchange_token_for_search()
  │           └── MSAL: acquire_token_on_behalf_of()
  │                 scope: https://search.azure.com/user_impersonation
  ├── AzureOpenAI クライアントを生成
  └── run_chat_loop()
        └── responses.create(
              model=model_deployment,
              tools=[{
                type: "mcp",
                server_url: kb_mcp_url,
                project_connection_id: foundryIQ-docsacl,
                headers: {"x-ms-query-source-authorization": user_token}
              }]
            )
              → AI Search が user_token のグループでドキュメントをフィルタ
              → LLM が検索結果を元に回答
```

---

### シナリオ 3: ACL あり — クラシック RAG パターン (`acl_on_classic-rag/`)

Foundry IQ を使わず、Azure OpenAI と Azure AI Search を直接組み合わせるクラシック RAG です。OBO フローで取得した JWT を自前でデコードしてグループ ID を抽出し、Search の `filter` パラメータに適用します。

**必要な環境変数**

| 変数名 | 説明 |
|---|---|
| `PROJECT_ENDPOINT` | AI Foundry Project のエンドポイント URL (テレメトリ用) |
| `MODEL_DEPLOYMENT` | チャットモデルのデプロイ名 |
| `OPENAI_ENDPOINT` | Azure OpenAI エンドポイント URL |
| `SEARCH_ENDPOINT` | Azure AI Search エンドポイント URL |
| `INDEX_NAME` | 検索インデックス名 (デフォルト: `index-acl-gen2`) |
| `AZURE_OBO_CLIENT_ID` | Entra ID アプリの Client ID |
| `AZURE_OBO_CLIENT_SECRET` | Entra ID アプリの Client Secret |
| `AZURE_OBO_TENANT_ID` | テナント ID |
| `OTEL_SERVICE_NAME` | OpenTelemetry サービス名 |

**実行**

```bash
export PROJECT_ENDPOINT="https://<foundry>.services.ai.azure.com/api/projects/aiproject"
export MODEL_DEPLOYMENT="gpt-4o"
export OPENAI_ENDPOINT="https://<foundry>.services.ai.azure.com"
export SEARCH_ENDPOINT="https://<ais>.search.windows.net"
export INDEX_NAME="index-acl-gen2"
export AZURE_OBO_CLIENT_ID="<client_id>"
export AZURE_OBO_CLIENT_SECRET="<client_secret>"
export AZURE_OBO_TENANT_ID="<tenant_id>"
export OTEL_SERVICE_NAME="classic-rag-demo"
python acl_on_classic-rag/main.py
```

**処理フロー**

```
main.py
  ├── OBO フローでユーザートークンを取得
  ├── JWT デコードでグループ ID を抽出
  │     → security_filter = "GroupIds/any(g: search.in(g, '<group_ids>'))"
  └── run_chat_loop()
        ├── [1] キーワード抽出 (chat.completions.create)
        ├── [2] AI Search で検索 (semantic + vector, filter=security_filter)
        │         VectorizableTextQuery を使用 (snippet_vector フィールド)
        └── [3] 回答生成 (chat.completions.create)
```

---

## シナリオ比較

| 項目 | `acl_off` | `acl_on` | `acl_on_classic-rag` |
|---|---|---|---|
| ACL | なし | あり | あり |
| ゲートウェイ | APIM → Foundry Agent | APIM → Foundry IQ (MCP) | APIM → Azure OpenAI / AI Search |
| 認証 | DefaultAzureCredential | OBO フロー | OBO フロー + JWT デコード |
| RAG | Foundry Agent が自動 | Foundry IQ が自動 | 自前実装 |
| API | `responses.create` (agent) | `responses.create` (MCP tool) | `chat.completions` + Search |
| 複雑さ | 低 | 中 | 高 |

---

## インフラのデプロイ

[Azure Developer CLI (azd)](https://learn.microsoft.com/ja-jp/azure/developer/azure-developer-cli/) を使用してデプロイします。

```bash
# ログイン
az login
azd auth login

# 初期化・デプロイ
azd up
```

デプロイ後、Terraform は以下のスクリプトを自動実行します:

- `infra/scripts/ais_set_noacl_index.sh` — ACL なしインデックスの作成
- `infra/scripts/ais_set_acl_index.sh` — ACL ありインデックスの作成
- `infra/scripts/ais_set_knowledge.sh` — ナレッジベースの作成

---

## 依存ライブラリ

```
azure-identity==1.25.1
azure-ai-projects==2.0.0b3
azure-monitor-opentelemetry==1.8.2
opentelemetry-api==1.39.0
opentelemetry-sdk==1.39.0
openai==2.15.0
httpx==0.28.1
msal==1.34.0
azure.search.documents==11.6.0
```

`appcodes/requirements.txt` を参照してください。

---

## ディレクトリ構成

```
.
├── appcodes/
│   ├── requirements.txt
│   ├── acl_off/                   # シナリオ 1: ACL なし
│   │   ├── main.py
│   │   └── modules/
│   │       ├── config.py          # 環境変数の読み込み
│   │       ├── auth_utils.py
│   │       ├── response_api.py    # Foundry Agent 呼び出し
│   │       └── telemetry_utils.py
│   ├── acl_on/                    # シナリオ 2: ACL あり (Foundry IQ)
│   │   ├── main.py
│   │   └── modules/
│   │       ├── config.py          # OBO 関連環境変数を含む
│   │       ├── auth_utils.py      # MSAL OBO フロー
│   │       ├── response_api.py    # MCP ツール呼び出し
│   │       └── telemetry_utils.py
│   └── acl_on_classic-rag/        # シナリオ 3: ACL あり (クラシック RAG)
│       ├── main.py
│       └── modules/
│           ├── config.py
│           ├── auth_utils.py      # OBO + JWT デコード
│           ├── openai_ais_api.py  # Search + OpenAI 直接呼び出し
│           └── telemetry_utils.py
├── infra/
│   ├── main.tf                    # 主要リソース定義
│   ├── variables.tf
│   ├── modules/
│   │   ├── AI/
│   │   │   ├── AIservice/         # AI Foundry
│   │   │   └── AIsearch/          # Azure AI Search
│   │   ├── gateway/
│   │   │   ├── apim/              # API Management
│   │   │   └── apim-api/
│   │   │       ├── foundry-agent/ # Foundry Agent API
│   │   │       ├── openai/        # OpenAI API
│   │   │       └── cognitiveservices/
│   │   └── storage/               # ADLS Gen2
│   └── scripts/                   # インデックス / KB 作成スクリプト
└── docs/                          # インデックス対象ドキュメント
```
