# セキュリティ

## APIM によるゲートウェイ制御

Azure API Management はすべてのリクエストの入口として機能し、Foundry エンドポイントへの直接アクセスを遮断します。  
`infra/modules/gateway/apim-api` 配下のポリシーで以下の制御が実装されています。

### 1. Entra ID トークン検証（`validate-azure-ad-token`）

**プロダクトポリシー** ([foundryagent_product_v2.xml](../../infra/modules/gateway/apim-api/foundry-agent/files/policy/foundryagent_product_v2.xml)) で、すべてのリクエストに対して Entra ID トークンを検証しています。

```xml
<validate-azure-ad-token
    tenant-id="{{EntraIDTenantId}}"
    output-token-variable-name="jwt"
    header-name="Authorization"
    failed-validation-httpcode="401"
    failed-validation-error-message="Unauthorized. Access token is missing or invalid.">
    <audiences>
        <audience>https://ai.azure.com/</audience>
    </audiences>
</validate-azure-ad-token>
```

検証後、JWT の `groups` クレームを取得し、許可グループに所属していない場合は `401` を返します。

```xml
<!-- groups クレームで許可グループを確認 -->
<set-variable name="allowedGroupIds" value="{{EntraIDGroup}}" />
<!-- isClientMatch || isGroupMatch のどちらでもなければ 401 -->
```

OpenAI エンドポイント ([aoai_operation_v2.xml](../../infra/modules/gateway/apim-api/openai/files/policy/aoai_operation_v2.xml)) では、AI Search のマネージド ID（`AIS-MI-CLIENT-ID`）もホワイトリストに追加されており、インデクサーからの内部呼び出しも許可しています。

### 2. トークン制御（TPM レート制限・クォータ）

**API ポリシー** ([foundryagent_api_v2.xml](../../infra/modules/gateway/apim-api/foundry-agent/files/policy/foundryagent_api_v2.xml)) で `llm-token-limit` によるトークン制御が実装されています。

```xml
<!-- TPM（Tokens Per Minute）レート制限 + クォータを組み合わせ -->
<llm-token-limit
    counter-key="@(product/<product_id>/deployment/<model>)"
    tokens-per-minute="@(int.Parse(tokenLimitValue))"
    token-quota="@(long.Parse(tokenQuotaValue))"
    token-quota-period="Hourly|Daily|Weekly|Monthly|Yearly"
    estimate-prompt-tokens="false" />
```

カウンターキーに **プロダクト ID × デプロイ名** を使用しているため、製品（チーム・プロジェクト）単位でトークン使用量を分離管理できます。`main.tfvars.json` の `tpm_limit_token` で TPM 上限を設定します。

> **なぜ OpenAI エンドポイントに `llm-token-limit` を設定しないのか**  
> Foundry IQ のエージェンティック リトリーバルは、クエリ受信時に内部で Azure OpenAI を呼び出し、複合クエリをサブクエリに分解（クエリプランニング）したり、回答合成（Answer Synthesis）を行います。この内部 LLM 呼び出しも OpenAI エンドポイントを経由するため、OpenAI 側に `llm-token-limit` を設定するとエージェンティック リトリーバルのトークン消費がカウントされ、**検索パイプライン自体がレート制限に引っかかる**おそれがあります。そのため、ユーザーリクエストが通過する Foundry Agent エンドポイント側にのみトークン制御を適用しています。
>
> | エンドポイント                       | `llm-token-limit` | 理由                                                                        |
> | ------------------------------------ | ----------------- | --------------------------------------------------------------------------- |
> | Foundry Agent API (`/foundryagent/`) | ✅ 適用           | ユーザーリクエスト単位で TPM 制御                                           |
> | OpenAI API (`/openai/`)              | ❌ 適用しない     | Foundry IQ エージェンティック リトリーバルの内部 LLM 呼び出しを妨げないため |

また、OpenAI 操作ポリシーでは `llm-emit-token-metric` によりトークン使用量をメトリクスとして Application Insights に送信しています。

```xml
<llm-emit-token-metric namespace="aif-aisearch">
    <dimension name="Client ID" value="@(...)" />
    <dimension name="Access Type" value="ManagedIdentity|UserContext" />
</llm-emit-token-metric>
```

### 3. セッションアフィニティ

バックエンドプールには `SessionId` Cookie ベースのセッションアフィニティが設定されています。  
同一セッション内のリクエストは同じ Foundry インスタンスにルーティングされるため、会話コンテキストの一貫性が保たれます。

```hcl
# foundry-agent.tf（バックエンドプール設定）
sessionAffinity = {
  sessionId = {
    name   = "SessionId"
    source = "cookie"
  }
}
```

### 4. サーキットブレーカー

バックエンド個別に**サーキットブレーカー**が設定されており、5 分以内に 3 回失敗（429 / 5xx）したバックエンドは 1 分間プールから除外されます。これにより 1 リージョンに障害が発生しても他リージョンへの自動フェイルオーバーが行われます。

---

## Foundry ガードレール

Azure AI Foundry の **Guardrails**（旧 Content Safety / Guardrails & Controls）は、LLM とエージェントへの入出力に対してリスク検出・ブロックを行う組み込みの安全機能です。  
**ガードレール**は複数の**コントロール**の名前付きコレクションです。コントロールごとにリスク種別・介入ポイント・アクションを定義します。

### 介入ポイント

| 介入ポイント                | モデル | エージェント | 説明                                         |
| --------------------------- | ------ | ------------ | -------------------------------------------- |
| **User input**              | ✅     | ✅           | ユーザーからのプロンプト                     |
| **Tool call** (preview)     | ❌     | ✅           | エージェントがツールに送るアクション・データ |
| **Tool response** (preview) | ❌     | ✅           | ツールからエージェントへの返答内容           |
| **Output**                  | ✅     | ✅           | モデル/エージェントからユーザーへの最終出力  |

> エージェントに独自のガードレールを割り当てると、モデル側のガードレールは**完全に上書き**されます。  
> 未割り当ての場合はエージェントが使うモデルデプロイのガードレールを継承します。

### 主なリスクとコントロール

| リスク                                   | モデル | エージェント | 概要                                                               |
| ---------------------------------------- | ------ | ------------ | ------------------------------------------------------------------ |
| **Hate / Violence / Sexual / Self-harm** | ✅     | ✅           | 4 段階（Low / Medium / High）の閾値でフィルタ                      |
| **User prompt attacks**                  | ✅     | ✅           | ジェイルブレイク攻撃（Prompt Shields）を検出・ブロック             |
| **Indirect attacks**                     | ✅     | ✅           | RAG ドキュメントに埋め込まれた間接プロンプトインジェクションを検出 |
| **Protected material**                   | ✅     | ✅           | 著作権テキスト・コードの出力を制御                                 |
| **Groundedness** (preview)               | ✅     | ❌           | ドキュメントと無関係な「ハルシネーション」応答を検出               |
| **PII** (preview)                        | ✅     | ✅           | 個人情報を出力にアノテーション・ブロック                           |
| **Task Adherence**                       | ✅     | ✅           | システムプロンプトへの準拠度を評価                                 |
| **Spotlighting** (preview)               | ✅     | ❌           | 外部ドキュメントを Base64 エンコードして信頼度を下げる追加防御層   |

デフォルト（**Microsoft.DefaultV2**）は Medium 閾値が全テキストモデルに適用されます。

### 設定方法

Foundry ポータルの左ナビから **Guardrails → Create guardrail** でリスク・介入ポイント・アクション（Annotate / Annotate and block）を選択し、モデルデプロイまたはエージェントに割り当てます。

```python
# Agent Framework Middleware でプロンプトシールドを組み込む例
from langchain_azure_ai.agents.middleware import AzurePromptShieldMiddleware

agent = create_agent(
    model=model,
    middleware=[
        AzurePromptShieldMiddleware(exit_behavior="error")  # 検出時に例外送出
    ],
)
```

### Foundry ガードレール vs Azure Language Service PII 検出

Foundry ガードレールの Content Filtering は PII 検出もサポートしていますが、**PII が検出された場合は出力全体をブロック**します。テキストを保持しつつ PII 部分のみをマスキングしたい場合は **Azure Language Service PII Detection API** の利用を推奨します。

| 観点               | Foundry ガードレール (Content Filtering)    | Azure Language Service PII Detection               |
| ------------------ | ------------------------------------------- | -------------------------------------------------- |
| 対応範囲           | ハーム全般（Hate / Violence / Sexual など） | PII 特化（氏名・住所・電話番号など）               |
| PII 検出時の挙動   | 出力全体をブロック                          | **PII 部分のみマスキング**（4 種のポリシー）       |
| 信頼度スコア閾値   | カテゴリ単位で設定                          | エンティティ種別ごとに設定可能                     |
| PII エンティティ数 | 限定的（主要カテゴリのみ）                  | **約 140 以上**（50 か国の国別 ID 含む）           |
| 日本語 ID 対応     | なし                                        | **あり**（マイナンバー・運転免許証・パスポート等） |
| 利用シーン         | 有害コンテンツ全般の防御                    | 監査ログの匿名化・コンプライアンス対応             |

Azure Language Service PII Detection がサポートする **日本固有 ID** の例：

| エンティティ                   | 説明                           |
| ------------------------------ | ------------------------------ |
| `JPMyNumberPersonal`           | マイナンバー（個人番号・12桁） |
| `JPMyNumberCorporate`          | 法人番号（13桁）               |
| `JPDriversLicenseNumber`       | 運転免許証番号                 |
| `JPPassportNumber`             | パスポート番号                 |
| `JPResidenceCardNumber`        | 在留カード番号                 |
| `JPResidentRegistrationNumber` | 住民票コード（11桁）           |
| `JPSocialInsuranceNumber`      | 社会保険番号（基礎年金番号等） |
| `JPBankAccountNumber`          | 銀行口座番号                   |

詳細は [Azure Language Service PII 検出実装ガイド](../../knowleage/Azure_Language_Service_PII_Detection_Guide.md) を参照してください。

---

## インフラセキュリティ（Terraform 設定）

`infra/main.tf` で以下のセキュリティ設定が適用されています。

| リソース             | 設定                              | 値              | 効果                                                  |
| -------------------- | --------------------------------- | --------------- | ----------------------------------------------------- |
| AI Foundry           | `disableLocalauth`                | `true`          | API キー認証を無効化。Entra ID トークン認証のみ許可   |
| AI Search            | `local_authentication_enabled`    | `false`         | API キー認証を無効化。Entra ID トークン認証のみ許可   |
| ストレージ           | `shared_access_key_enabled`       | `false`         | SAS キー・共有アクセスキーを無効化。Entra ID 認証のみ |
| ストレージ           | `allow_nested_items_to_be_public` | `false`         | BLOB の匿名パブリックアクセスを禁止                   |
| Application Insights | `local_authentication_disabled`   | `false`（有効） | Foundry の仕様により接続文字列認証を維持（後述）      |

> **Application Insights のローカル認証について**  
> Foundry が Application Insights と連携する際、接続文字列（ローカル認証）が必要なため、Application Insights のみローカル認証を有効化しています。接続文字列は環境変数に直書きせず **Foundry Connection** に格納し、Python SDK で取得しています（後述）。

---

## Foundry Connection

**Foundry Connection** は、外部サービスへのアクセス設定を再利用可能な形で管理する仕組みです。  
API キー・接続文字列などのシークレットを安全に保管するだけでなく、マネージド ID や Entra ID パススルーによる**アイデンティティブローカー**としても機能します。

接続はスコープに応じて2つのレベルで作成できます。

| スコープ | 用途 |
|---|---|
| **Foundry リソースレベル** | Azure Storage・Key Vault などの共有サービスへの接続 |
| **プロジェクトレベル** | 機密性の高いデータや特定プロジェクト固有の接続 |

主な接続タイプは Azure AI Search、Azure OpenAI、Application Insights、Azure Key Vault、Custom Keys など多数サポートされています（詳細は [公式ドキュメント](https://learn.microsoft.com/azure/foundry/how-to/connections-add) 参照）。

### 認証タイプ

| タイプ | 説明 |
|---|---|
| **API キー / カスタムキー** | キー・バリューペアでシークレットを格納 |
| **Entra ID（マネージド ID）** | マネージド ID でリソースへアクセス。シークレット不要 |
| **Entra ID パススルー** | ユーザートークンをそのまま外部サービスに委譲 |

### Python SDK での取得

```python
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

project_client = AIProjectClient(endpoint=project_endpoint, credential=DefaultAzureCredential())

# ⚠️ include_credentials=True が必須（デフォルトは False）
conn = project_client.connections.get(
    name="appi-connection",   # Connection 名
    include_credentials=True
)
connection_string = conn.credentials.api_key   # ApiKey 型の場合
```

`CustomKeys` 型の場合は `conn.credentials.credential_keys["KEY_NAME"]` でアクセスします。  
詳細は [Foundry SDK Connections API ガイド](../../knowleage/Foundry_SDK_Connections_API_Guide.md) を参照してください。

### Application Insights との連携

本ハンズオンでは Application Insights の接続文字列を Foundry Connection（`appi-connection`）に格納し、アプリ起動時に SDK で取得しています。  
Foundry の仕様として Application Insights との連携に接続文字列（ローカル認証）が必要なためです。

### シークレットの格納先（Key Vault）

Connection のシークレットはデフォルトで Foundry が管理する Key Vault（サブスクリプション外）に保管されます。  
自組織の Key Vault で一元管理したい場合は BYO（Bring Your Own）Key Vault として接続できます。

| 格納先 | 特徴 |
|---|---|
| Microsoft マネージド（デフォルト） | サブスクリプション外で管理不要。設定不要 |
| 自前の Key Vault（BYO） | 自社で一元管理可能。Foundry ポータルの **Connections → Azure Key Vault** で接続 |

> BYO Key Vault はリソースごとに 1 つのみ接続可能。シークレットの移行（既存 Connection の移植）は非サポート。Key Vault を削除すると Foundry リソース全体が破損するため注意。

---

## 次のステップ

- [AI 評価 (Continuous Evaluation) と Observability](./03_evaluation_observability.md)
