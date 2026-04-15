# Microsoft Foundry × Microsoft Purview 連携ガイド

> **参考**: [公式ドキュメント](https://learn.microsoft.com/purview/ai-azure-foundry)  
> **開発者向け**: [Purview 連携開発ガイド](https://learn.microsoft.com/purview/developer/secure-ai-with-purview)

---

## 概要

Microsoft Purview を Azure サブスクリプションで有効化することで、Microsoft Foundry の**アプリとエージェント**からのプロンプト・レスポンスデータ（関連メタデータ含む）にアクセス・処理・保存が可能になる。

> 出典: [Manage compliance and security in Microsoft Foundry](https://learn.microsoft.com/azure/foundry/control-plane/how-to-manage-compliance-security)  
> "By enabling Microsoft Purview on your Azure subscription, you can access, process, and store prompt and response data from Microsoft Foundry **apps and agents**."

---

## Data Security ポリシーの適用範囲

Microsoft Purview **Data Security ポリシー**は、Foundry のマネージド推論エンドポイント (`/chat/completions`) に対して **Entra ID ユーザーコンテキスト認証** を使用する操作に適用される。  
詳細: [AzureUserSecurityContext](https://learn.microsoft.com/azure/foundry/openai/latest#azureusersecuritycontext)

| 対象                                                    | Purview 統合                                                    |
| ------------------------------------------------------- | --------------------------------------------------------------- |
| `/chat/completions` + Entra ID ユーザーコンテキスト認証 | ✓ 監査・DSPM・DLP ポリシー等**すべて適用**                      |
| 上記以外の認証シナリオ                                  | 監査・DSPM Activity Explorer での**閲覧のみ**。ポリシー適用なし |

### 認証シナリオ別の機能対応詳細

| 機能カテゴリ             | `/chat/completions` + ユーザーコンテキスト認証 | それ以外の認証シナリオ |
| ------------------------ | ---------------------------------------------- | ---------------------- |
| 監査 (Audit)             | ✓                                              | ✓（閲覧可能）          |
| DSPM for AI              | ✓                                              | ✓（分類・閲覧可能）    |
| データ分類 (SIT)         | ✓                                              | ✓（分類・閲覧可能）    |
| DLP ポリシー適用         | ✓                                              | ✕（適用されない）      |
| インサイダーリスク管理   | ✓                                              | 分類のみ               |
| Communication Compliance | ✓                                              | 分類のみ               |

---

## Foundry エージェントの Purview 対応状況

[Use Microsoft Purview for AI agents](https://learn.microsoft.com/purview/ai-agents) によると、Microsoft Foundry エージェントは以下の Purview 機能に対応している：

| 対応項目                               | 状況 |
| -------------------------------------- | ---- |
| DSPM for AI                            | ✓    |
| データ分類                             | ✓    |
| 機密度ラベル                           | ✓    |
| DLP                                    | ✓    |
| インサイダーリスク管理                 | ✓    |
| 情報保護 (AI interactions)             | ✓    |
| コンプライアンス管理 (AI interactions) | ✓    |

> ※ ネットワーク分離は Purview 統合では未サポート。

---

## サポートされる Purview 機能一覧

| Purview 機能                           | 対応 | 概要                                                                                             |
| -------------------------------------- | ---- | ------------------------------------------------------------------------------------------------ |
| **DSPM for AI**                        | ✓    | AI 利用の検出・セキュリティ態勢管理。ワンクリックポリシーによるプロンプト/レスポンスの取得・分析 |
| **監査 (Audit)**                       | ✓    | プロンプトとレスポンスを統合監査ログに記録。いつ・どのように・誰がAIアプリとやり取りしたかを追跡 |
| **データ分類**                         | ✓    | 機密情報タイプ (SIT) でプロンプト/レスポンス内の機密データを検出・分類                           |
| **機密度ラベル**                       | ✓    | AI Search 経由で RAG データソースにラベルベースのアクセス制御を適用                              |
| **データ損失防止 (DLP)**               | ✓    | 機密情報を含むプロンプトのブロック。API またはAgent Framework で適用                             |
| **インサイダーリスク管理**             | ✓    | プロンプトインジェクション攻撃や保護対象資料へのアクセスなどリスクのある AI 使用を検出           |
| **コミュニケーションコンプライアンス** | ✓    | ハラスメント・脅迫・機密情報共有などの不適切なプロンプト/レスポンスを検出                        |
| **eDiscovery**                         | ✓    | 法的・規制要件に対応するためのAIやり取りデータの検索・保持                                       |
| **データライフサイクル管理**           | ✓    | 保持ポリシー・アーカイブによるAIデータの適切な管理                                               |
| **Compliance Manager**                 | ✓    | GDPR/HIPAAなどの規制テンプレートに基づくコンプライアンス評価                                     |
| 暗号化（ラベルなし）                   | ✕    | 非対応                                                                                           |

---

## 連携シナリオと実現方法

### シナリオ別の対応表

| シナリオ                       | Foundry ネイティブ | Agent Framework | Purview API |
| ------------------------------ | ------------------ | --------------- | ----------- |
| ランタイムガバナンス（監査等） | ✓                  | ✓               | ✓           |
| データ漏洩・DLP 防止           | ✕                  | ✓               | ✓           |
| データ過剰共有防止             | ✕                  | ✕               | ✓           |

### 1. ランタイムデータのガバナンス（監査・分類・DSPM）

3つの方法から選択可能：

| 方法                               | 説明                                                                                                                                                                                       |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Foundry ネイティブ統合（推奨）** | Foundry ポータルの Compliance 設定で Purview トグルを ON にする。開発者側のコード変更不要。Data Security ポリシーの適用は `/chat/completions` + ユーザーコンテキスト認証の呼び出しが対象。 |
| **Purview API (Graph)**            | `processContent` API でプロンプト/レスポンスを Purview に送信                                                                                                                              |
| **Agent Framework**                | ミドルウェアパイプラインに Purview ポリシーミドルウェアを追加                                                                                                                              |

### 2. データ漏洩・インサイダーリスク防止（DLP）

| 方法                | 説明                                                             |
| ------------------- | ---------------------------------------------------------------- |
| **Agent Framework** | Purview SDK ミドルウェアを組み込み、DLP ポリシーを適用           |
| **Purview API**     | `computeProtectionScopes` + `processContent` API で DLP チェック |

> Foundry ネイティブ統合では DLP 適用は非対応。API または Agent Framework が必要。

### 3. データの過剰共有防止（機密度ラベル）

| 方法                                 | 説明                                                                         |
| ------------------------------------ | ---------------------------------------------------------------------------- |
| **Azure AI Search + Purview ラベル** | インデクサーでラベルを取り込み、クエリ時にアクセス制御（別ドキュメント参照） |
| **Purview API (Graph)**              | ラベル情報を直接取得して独自に制御                                           |

> Foundry ネイティブ・Agent Framework では非対応。API ベースの統合が必要。

---

## 有効化の手順

### Foundry ポータルでの有効化

**前提**: Azure AI Account Owner ロールが必要

1. ツールバーで **Operate** を選択
2. 左ペインで **Compliance** を選択
3. **Security posture** タブを選択
4. Azure サブスクリプションを選択
5. **Microsoft Purview** トグルを ON にする

複数のサブスクリプションがある場合は、それぞれで繰り返す。

### 代替: Defender for Cloud からの有効化

Azure ポータルの Microsoft Defender for Cloud で「Enable Data Security for Azure AI with Microsoft Purview」を設定する。

---

## 前提条件・課金

- テナントに **Microsoft Purview ライセンス** が必要
- ポリシー管理には **Pay-as-you-go 課金**の有効化が必要
- 監査 (Audit) のみは Purview ライセンスに含まれる（追加課金なし）
- ネットワーク分離は Purview 統合では**未サポート**

---

## 開発者向け: Purview API

### ランタイムガバナンス用 API

| API                                                                                                   | 用途                                     |
| ----------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| [computeProtectionScopes](https://learn.microsoft.com/graph/api/userprotectionscopecontainer-compute) | 保護スコープの計算                       |
| [processContent](https://learn.microsoft.com/graph/api/userdatasecurityandgovernance-processcontent)  | プロンプト/レスポンスの処理・DLPチェック |

### 機密度ラベル関連 API

| API                                                                                                                     | 用途                    |
| ----------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| [List sensitivity labels](https://learn.microsoft.com/graph/api/tenantdatasecurityandgovernance-list-sensitivitylabels) | ラベル一覧取得          |
| [Get sensitivity label](https://learn.microsoft.com/graph/api/sensitivitylabel-get)                                     | GUID からラベル詳細取得 |
| [List usage rights](https://learn.microsoft.com/graph/api/usagerightsincluded-get)                                      | 使用権一覧取得          |
| [Compute inheritance](https://learn.microsoft.com/graph/api/sensitivitylabel-computeinheritance)                        | ラベル継承の計算        |
| [Compute rights and inheritance](https://learn.microsoft.com/graph/api/sensitivitylabel-computerightsandinheritance)    | 権限と継承の計算        |

### Agent Framework での Purview 統合

Microsoft Agent Framework SDK に Purview ポリシーミドルウェアを追加することで、エージェントの入出力に対して DLP ポリシーの適用やガバナンスが可能。

- Python: `pip install agent-framework --pre`
- 詳細: [Use Microsoft Purview SDK with Agent Framework](https://learn.microsoft.com/agent-framework/integrations/purview)

---

## Azure AI Search 機密度ラベルとの関係

Azure AI Search の Purview 機密度ラベル連携は **AI Search 側の機能**であり、Foundry の Data Security ポリシー適用範囲とは独立して動作する。

`x-ms-query-source-authorization` ヘッダーによるクエリ時アクセス制御は、エージェント経由でも AI Search に対して有効。

詳細は [Azure_AI_Search_Purview_Sensitivity_Labels_Guide.md](Azure_AI_Search_Purview_Sensitivity_Labels_Guide.md) を参照。

---

## Microsoft Defender for Cloud × Microsoft Foundry 連携ガイド

> **参考**: [Manage compliance and security in Microsoft Foundry](https://learn.microsoft.com/azure/foundry/control-plane/how-to-manage-compliance-security)
>
> [AI security posture management with Defender for Cloud](https://learn.microsoft.com/azure/defender-for-cloud/ai-security-posture)

---

## 概要

Microsoft Defender for Cloud は、Microsoft Foundry 上の AI ワークロードに対して、

- **セキュリティ体制（ポスチャ）推奨事項の可視化**
- **脅威検出（ジェイルブレイク・プロンプト攻撃等）**
- **リスクベースの優先順位付け・修復アクション**
  を提供します。

### 主な可視化・管理ポイント

| 項目                        | Foundry ポータル           | Azure/Defender XDR ポータル |
| --------------------------- | -------------------------- | --------------------------- |
| Defender for Cloud 推奨事項 | ◯（Security posture タブ） | ◯（統合ビュー・詳細分析）   |
| リスクレベル・修復リンク    | ◯                          | ◯                           |
| 攻撃パス分析・AI BOM        | ×                          | ◯                           |
| 統合スコアリング            | ×                          | ◯                           |

---

## 連携の仕組み

- **Security posture タブ**（Foundryポータル）で、Defender for Cloud の推奨事項（リスクレベル付き）を一覧表示
- **Risks + alerts**（プロジェクト単位）で、Defender for Foundry Tools による脅威アラート・推奨事項を確認
- **修復アクション**は Azure portal へのリンクで実施
- **Defender CSPM（有料）**を有効化すると、AI Bill of Materials（AI BOM）、攻撃パス分析、IaC 設定ミス検出などの高度な可視化が Azure/Defender XDR ポータルで利用可能

---

## 代表的な可視化・推奨事項の例

- **AI ワークロードの脆弱性・設定ミス検出**
- **AI サービスのエンドポイント制限/Private Endpoint 推奨**
- **マネージド ID/ID ベース認証の推奨**
- **攻撃パス分析によるデータ露出経路の可視化**
- **ジェイルブレイク・プロンプト攻撃のアラート**

---

## 参考リンク

- [AI security posture management with Defender for Cloud](https://learn.microsoft.com/azure/defender-for-cloud/ai-security-posture)
- [Manage compliance and security in Microsoft Foundry](https://learn.microsoft.com/azure/foundry/control-plane/how-to-manage-compliance-security)
- [Review security recommendations](https://learn.microsoft.com/azure/defender-for-cloud/review-security-recommendations)
