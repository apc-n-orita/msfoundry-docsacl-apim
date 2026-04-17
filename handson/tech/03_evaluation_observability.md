# AI 評価 (Continuous Evaluation) と Observability

## AI 評価 — Continuous Evaluation

### 概要

**Continuous Evaluation** は、実運用で動作中のエージェントの回答品質・安全性を継続的に評価する機能です。  
エージェントのレスポンス完了イベントをトリガーに評価ルールが起動し、サンプリングされたやり取りを自動評価します。品質低下や安全上の問題を早期に検知できます。

### 評価のライフサイクル

Foundry の評価は 3 つのステージで構成されます。

| ステージ               | 目的                                   | 主なツール                                   |
| ---------------------- | -------------------------------------- | -------------------------------------------- |
| **モデル選定**         | ベースモデルの品質・安全性を比較       | Foundry ベンチマーク / Evaluation SDK        |
| **本番前評価**         | デプロイ前の品質検証、エッジケース確認 | Foundry ポータル / Azure AI Evaluation SDK   |
| **本番後モニタリング** | 継続的品質監視・ドリフト検知           | **Continuous Evaluation** / スケジュール評価 |

### Agent Monitoring Dashboard

Foundry ポータルの **Build → エージェント選択 → Monitor タブ** から一元管理します。

| 指標                    | 説明                                                                              |
| ----------------------- | --------------------------------------------------------------------------------- |
| **Token usage**         | トークン消費量。大きい場合はプロンプト最適化の余地あり                            |
| **Latency**             | エージェント実行の応答時間。10 秒超はモデルスロットルや複雑なツール呼び出しを示唆 |
| **Run success rate**    | 実行の成功率。95% 未満は要調査                                                    |
| **Evaluation metrics**  | 継続的評価器が生成したスコア                                                      |
| **Red teaming results** | スケジュール済みレッドチームスキャンの結果                                        |

Monitor タブの **Settings（歯車アイコン）** から以下を設定できます。

| 設定                            | 用途                                               |
| ------------------------------- | -------------------------------------------------- |
| Continuous evaluation           | 評価器の追加・サンプリングレート設定               |
| Scheduled evaluations (preview) | スケジュール実行による定期ベンチマーク             |
| Red team scans (preview)        | 敵対的テストによるセキュリティリスク検出           |
| Alerts (preview)                | レイテンシ・評価スコア・レッドチーム結果の異常通知 |

### 主な評価メトリクス

| カテゴリ         | 評価項目                             | 内容                                                |
| ---------------- | ------------------------------------ | --------------------------------------------------- |
| **エージェント** | Task Completion (preview)            | タスクを最後まで完遂できたか（Pass/Fail）           |
|                  | Task Adherence (preview)             | システム指示・制約への準拠度（Pass/Fail）           |
|                  | Intent Resolution (preview)          | ユーザー意図の解釈精度（Pass/Fail）                 |
|                  | Task Navigation Efficiency           | 最適なステップ数でタスクを達成できたか（Pass/Fail） |
|                  | Tool Call Accuracy                   | ツール選択・パラメータ・効率の総合評価              |
|                  | Tool Selection                       | 最適なツールを選択できているか                      |
|                  | Tool Input Accuracy                  | ツール呼び出しパラメータの正確性                    |
|                  | Tool Output Utilization              | ツール出力を適切に活用できているか                  |
| **RAG 品質**     | Groundedness                         | 検索結果と回答の一致度                              |
|                  | Relevance                            | クエリに対する回答の関連性                          |
|                  | Coherence                            | 論理的一貫性                                        |
|                  | Fluency                              | 自然な言語品質                                      |
| **安全性**       | Violence / Hate / Sexual / Self-harm | 有害コンテンツの検出（LLM ジャッジ不要）            |

### 継続的評価の設定（SDK）

```bash
pip install "azure-ai-projects>=2.0.0"
```

**事前準備**: プロジェクトのマネージド ID に **Azure AI User** ロールを付与する。

```python
import os
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    EvaluationRule,
    ContinuousEvaluationRuleAction,
    EvaluationRuleFilter,
    EvaluationRuleEventType,
)

endpoint = os.environ["AZURE_AI_PROJECT_ENDPOINT"]

with (
    DefaultAzureCredential() as credential,
    AIProjectClient(endpoint=endpoint, credential=credential) as project_client,
    project_client.get_openai_client() as openai_client,
):
    # ① 評価オブジェクトを作成（使用する評価器を定義）
    eval_object = openai_client.evals.create(
        name="Continuous Evaluation",
        data_source_config={"type": "azure_ai_source", "scenario": "responses"},
        testing_criteria=[
            {"type": "azure_ai_evaluator", "name": "violence_detection",
             "evaluator_name": "builtin.violence"},
        ],
    )

    # ② 継続的評価ルールを作成（レスポンス完了時にトリガー）
    rule = project_client.evaluation_rules.create_or_update(
        id="my-continuous-eval-rule",
        evaluation_rule=EvaluationRule(
            display_name="My Continuous Eval Rule",
            action=ContinuousEvaluationRuleAction(
                eval_id=eval_object.id,
                max_hourly_runs=100,        # 時間あたりの最大実行数（デフォルト 100）
            ),
            event_type=EvaluationRuleEventType.RESPONSE_COMPLETED,
            filter=EvaluationRuleFilter(agent_name="<your-agent-name>"),
            enabled=True,
        ),
    )
    print(f"Rule created: {rule.id}")
```

評価結果は Application Insights に送信され、Foundry ポータルの **Monitor タブ** から確認できます。

### 活用パターン

- **CI/CD パイプラインへの組み込み**: デプロイ前の品質ゲートとして評価を実施
- **本番モニタリング**: 継続的評価でドリフトを早期検知
- **バージョン比較**: モデル・プロンプト更新前後で評価スコアを比較
- **レッドチームスキャン**: スケジュール実行でセキュリティリスクを定期検出

---

## Observability — トレース・メトリクス・ダッシュボード

### ハンズオンで確認した観測基盤

ハンズオンでは W3C TraceContext（`traceparent`）によりクライアント → APIM → AI Foundry、さらに Foundry IQ が呼び出す OpenAI エンドポイントまでを 1 本のトレースとして Application Insights に記録しました。

```
[クライアント]                                              ✅ 記録
     │ traceparent を生成・送信
     ▼
  [APIM]                                                    ✅ 記録
     │ traceparent を引き継ぎ・転送
     ▼
[AI Foundry]（Foundry Agent / Foundry IQ）                  ✅ 記録
     │
     ├─▶ [OpenAI] chat_completion / embedding               ✅ 記録（APIM 経由で traceparent 引き継ぎ）
     │
     └─▶ [AI Search]                                        ❌ 記録されない（トレース送信不可）
```

AI Search は Application Insights へトレースを送信できないため、Foundry IQ 内部の AI Search 呼び出しはトレース上に記録されません。OpenAI エンドポイント（APIM 経由）への呼び出しのみが同一 trace_id で紐づきます。

各シナリオで記録されるスパン属性は以下の通りです。

| スパン                           | 記録される主な属性                                                              |
| -------------------------------- | ------------------------------------------------------------------------------- |
| `user_chat_turn`（シナリオ 1/2） | `gen_ai.prompt`, `tokens.input/, tokens.total`                                  |
| `user_chat_turn`（シナリオ 3）   | `gen_ai.prompt`, `query_tokens.*`（検索クエリ生成）, `res_tokens.*`（回答生成） |

### Grafana Dashboard（予定）

> **注意**: Azure ポータル上で表示できる **Grafana Dashboard** を追加予定です。

---

## 次のステップ

- [Microsoft Foundry のさらなるセキュリティ強化](./04_advanced_security.md)

---

## 前のドキュメント

- [セキュリティ — APIM ゲートウェイ制御と Foundry ガードレール](./02_security.md)
