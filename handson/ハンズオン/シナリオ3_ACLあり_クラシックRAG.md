# シナリオ 3: ACL あり — クラシック RAG パターン

## 概要

Foundry IQ を使わず、Azure OpenAI と Azure AI Search を直接組み合わせるクラシック RAG です。
OBO フローで取得した JWT を自前でデコードしてグループ ID を抽出し、Search の `filter` パラメータに適用することで ACL を実現します。

シナリオ 2 と同じ ACL の結果を得ながら、Foundry IQ に依存しない実装の違いを体験します。

**使用コード**: `appcodes/acl_on_classic-rag/`

---

## 処理フロー

```
クライアント (acl_on_classic-rag/main.py)
  │
  │  [1] OBO フロー: AI Search 用トークンを取得
  │
  │  [2] JWT デコードでグループ ID を抽出
  │        groups: ["<group_id_1>", ...]
  │        → security_filter = "GroupIds/any(g: search.in(g, '<group_ids>'))"
  │
  ▼
run_chat_loop()
  │
  ├── [Step 1] キーワード抽出
  │     openai_client.chat.completions.create(
  │       model=model_deployment,
  │       messages=[{system: "検索クエリを作る"}, {user: user_input}]
  │     )
  │
  ├── [Step 2] AI Search で検索
  │     search_client.search(
  │       search_text=search_text,
  │       filter=security_filter,          ← グループフィルタ
  │       query_type="semantic",
  │       semantic_configuration_name="tartalia-semantic-configuration",
  │       vector_queries=[VectorizableTextQuery(fields="snippet_vector")]
  │     )
  │
  └── [Step 3] 回答生成
        openai_client.chat.completions.create(
          messages=[{system: "要約アシスタント"}, {user: 検索結果 + 質問}]
        )
```

---

## 環境変数

| 変数名                    | 説明                                                   | 例                                                               |
| ------------------------- | ------------------------------------------------------ | ---------------------------------------------------------------- |
| `PROJECT_ENDPOINT`        | AI Foundry Project のエンドポイント URL (テレメトリ用) | `https://<foundry>.services.ai.azure.com/api/projects/aiproject` |
| `MODEL_DEPLOYMENT`        | チャットモデルのデプロイ名                             | `gpt-4o`                                                         |
| `OPENAI_ENDPOINT`         | Azure OpenAI エンドポイント URL                        | `https://<foundry>.services.ai.azure.com`                        |
| `SEARCH_ENDPOINT`         | Azure AI Search エンドポイント URL                     | `https://<ais>.search.windows.net`                               |
| `INDEX_NAME`              | 検索インデックス名                                     | `index-acl-gen2`                                                 |
| `AZURE_OBO_CLIENT_ID`     | Entra ID アプリの Client ID                            | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`                           |
| `AZURE_OBO_CLIENT_SECRET` | Entra ID アプリの Client Secret                        | (環境構築で発行したシークレット)                                 |
| `AZURE_OBO_TENANT_ID`     | テナント ID                                            | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`                           |
| `OTEL_SERVICE_NAME`       | OpenTelemetry サービス名                               | `scenario3-classic-rag`                                          |

---

## 手順

### Step 1: 環境変数を設定する

```bash
export PROJECT_ENDPOINT="$(azd env get-value PROJECT_ENDPOINT)"
export MODEL_DEPLOYMENT="$(azd env get-value MODEL_DEPLOYMENT)"
export OPENAI_ENDPOINT="$(azd env get-value OPENAI_ENDPOINT)"
export SEARCH_ENDPOINT="$(azd env get-value SEARCH_ENDPOINT)"
export INDEX_NAME="index-acl-gen2"
export AZURE_OBO_CLIENT_ID="$(azd env get-value AZURE_OBO_CLIENT_ID)"
export AZURE_OBO_CLIENT_SECRET="$(az ad app credential reset --id "$AZURE_OBO_CLIENT_ID" --years 1 --append --query "password" -o tsv)"
export AZURE_OBO_TENANT_ID="$(azd env get-value AZURE_TENANT_ID)"
export OTEL_SERVICE_NAME="scenario3-classic-rag"
```

### Step 2: アプリを実行する

```bash
cd appcodes
source .venv/bin/activate  # Windows: .venv\Scripts\activate
python acl_on_classic-rag/main.py
```

起動時に OBO フローと JWT デコードが実行されます。

```
Azure AI Search 用トークン取得中（OBOフロー）...
=== AIモデル情報 ===
Model: gpt-4o
============================================================
対話を開始します。終了するには 'exit', 'quit', 'q' を入力してください。
============================================================

質問を入力してください:
ユーザー:
```

### Step 3: 質問を入力して 3 ステップの処理を観察する

```
ユーザー: タルタリアとはどんな文明ですか？
```

コンソールに以下の順で出力されることを確認します。

```
=== 検索クエリ生成中 ===
=== 検索実行中: 'タルタリア 文明' ===
=== 回答生成中 ===
=== 検索結果に基づく回答 ===

（回答テキスト）
```

3 ステップ (クエリ生成 → 検索 → 回答生成) が明示的に分離されており、各ステップの処理が可視化されています。

### Step 4: セキュリティフィルタの動作を確認する

OBO トークンを JWT としてデコードし、`groups` クレームからグループ ID を抽出して AI Search の `filter` パラメータを組み立てます。

所属グループがある場合、該当グループのドキュメントのみ返します:

```
security_filter = "GroupIds/any(g: search.in(g, '<adls-acl-group-id>'))"
```

グループ情報がトークンに含まれない場合は、`everyone` タグが付いたドキュメントのみ返します:

```
security_filter = "GroupIds/any(g: g eq 'everyone')"
```

### Step 5: シナリオ 2 との比較

同じ質問で比較すると、ACL の結果は同じですがアーキテクチャが異なります。

| 観点                | シナリオ 2 (`acl_on`)                      | シナリオ 3 (`acl_on_classic-rag`)      |
| ------------------- | ------------------------------------------ | -------------------------------------- |
| RAG の実装          | Foundry IQ が自動処理                      | 自前の 3 ステップ                      |
| ACL の適用方法      | `x-ms-query-source-authorization` ヘッダー | `filter` パラメータ (JWT デコード)     |
| Search クライアント | MCP (Foundry IQ 経由)                      | `azure.search.documents.SearchClient`  |
| API                 | `responses.create` (MCP tool)              | `chat.completions.create` × 2 + Search |
| 会話コンテキスト    | `previous_response_id` で自動管理          | 自前で管理が必要                       |

### Step 6: Application Insights でトレースを確認する

確認手順は[シナリオ 1 の Step 5](./シナリオ1_ACLなし.md#step-5-application-insights-でトレースを確認する) と同様です。

> **注意**: Foundry ポータルではシナリオ 3 のトレースは閲覧できません。Application Insights のみで確認してください。

`knowledge-classic-rag-session` > `user_chat_turn` スパンには以下のカスタム属性が記録されます。

| 属性名 | 内容 |
|---|---|
| `model_deployment` | 使用するモデルのデプロイ名 |
| `gen_ai.prompt` | ユーザーの入力テキスト |
| `query_tokens.input` | キーワード抽出の入力トークン数 |
| `query_tokens.output` | キーワード抽出の出力トークン数 |
| `query_tokens.total` | キーワード抽出の合計トークン数 |
| `query_tokens.input.cached` | キーワード抽出のキャッシュ済み入力トークン数 |
| `query_tokens.output.reasoning` | キーワード抽出の推論トークン数 |
| `res_tokens.input` | 回答生成の入力トークン数 |
| `res_tokens.output` | 回答生成の出力トークン数 |
| `res_tokens.total` | 回答生成の合計トークン数 |
| `res_tokens.input.cached` | 回答生成のキャッシュ済み入力トークン数 |
| `res_tokens.output.reasoning` | 回答生成の推論トークン数 |

### Step 7: 終了する

```
ユーザー: exit
```

---

## コード解説

### `acl_on_classic-rag/modules/openai_ais_api.py` — グループフィルタ構築

```python
# JWT デコード (署名検証なし — ローカルでの確認用)
decoded = jwt.decode(user_token, options={"verify_signature": False})
user_groups = decoded.get("groups", [])

if user_groups:
    group_ids_str = ",".join(user_groups)
    security_filter = f"GroupIds/any(g: search.in(g, '{group_ids_str}'))"
else:
    security_filter = "GroupIds/any(g: g eq 'everyone')"
```

### `acl_on_classic-rag/modules/openai_ais_api.py` — ベクトル + セマンティック検索

```python
results = search_client.search(
    search_text=search_text,
    filter=security_filter,                        # ACL フィルタ
    query_type="semantic",
    semantic_configuration_name="tartalia-semantic-configuration",
    vector_queries=[
        VectorizableTextQuery(
            text=search_text,
            fields="snippet_vector",               # 埋め込みベクトルフィールド
            k_nearest_neighbors=3
        )
    ],
    headers={"x-ms-enable-elevated-read": "true"}
)
```

ハイブリッド検索 (キーワード + ベクトル) とセマンティックランキングを組み合わせることで、高精度な検索結果を取得します。

## シナリオ全体の振り返り

3 つのシナリオを通じて、以下を体験しました。

| シナリオ   | 学んだこと                                                |
| ---------- | --------------------------------------------------------- |
| シナリオ 1 | Foundry Agent + Foundry IQ の基本的な呼び出し方           |
| シナリオ 2 | OBO フローによるユーザー代理認証と Foundry IQ の ACL 連携 |
| シナリオ 3 | クラシック RAG での自前 ACL 実装と Foundry IQ との比較    |

Foundry IQ を使うことで、ACL の適用・検索・回答生成を一括して委譲できる一方、クラシック RAG ではより細かい制御が可能になります。

## 次のステップ

アーキテクチャをより深く理解するための技術解説に進んでください。

→ **[技術解説を読む](../tech/tech.md)**

---

## 前のシナリオ

- [シナリオ 2 — ACL あり（Foundry IQ）](./シナリオ2_ACLあり_FoundryIQ.md)
