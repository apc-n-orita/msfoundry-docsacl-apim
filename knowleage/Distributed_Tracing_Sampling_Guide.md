# 分散トレース サンプリング実装ガイド（本プロジェクト版）

## 目次

1. [概要](#概要)
2. [本プロジェクトのトレース構成](#本プロジェクトのトレース構成)
   - [スパン階層](#スパン階層acloff--aclon-の代表)
   - [Parent-based Sampling の詳細メカニズム](#parent-based-sampling-の詳細メカニズム)
3. [サンプリング設定の意味](#サンプリング設定の意味)
   - [sampling_ratio vs traces_per_second](#アプリ側-samplingratio-vs-tracespersecond)
   - [APIM 側 sampling_percentage](#apim-側-samplingpercentage)
4. [実装ポイント（このリポジトリ）](#実装ポイントこのリポジトリ)
   - [propagator で TraceContext 注入](#1-propagator-で-tracecontext-注入重要な変更点)
   - [サンプリング設定と環境変数](#2-サンプリング設定python)
5. [検証手順（Application Insights / KQL）](#検証手順application-insights--kql)
   - [itemCount の詳細解説](#itemcount-フィールドの詳細解説)
   - [統計的検証の詳細](#統計的検証の詳細-なぜ-3-回では不十分か)
6. [トラブルシューティング](#トラブルシューティング)
7. [本番運用の推奨値と調整方針](#本番運用の推奨値と調整方針)
   - [トラフィック量別の推奨値](#トラフィック量別の推奨-samplingratio)
   - [初期設定の推奨手順](#初期設定の推奨手順)
   - [調整判断のための KQL ダッシュボード](#調整判断のための-kql-ダッシュボード)
   - [モニタリングアラートの設定](#モニタリングアラートの設定)

---

## 概要

このプロジェクトは OpenTelemetry を使って、ローカル SDK から APIM、Foundry 側までの分散トレースを収集しています。

主な収集レイヤー:

- アプリ側（Python）: Azure Monitor OpenTelemetry Distro
- ゲートウェイ側: APIM Diagnostic
- 伝播方式: W3C TraceContext（traceparent / tracestate）

### 本プロジェクトの現在の設定

**重要:** 本プロジェクトでは、アプリ側で **明示的なサンプリング設定を行っていません**。

```python
# 現在の実装（appcodes/*/modules/telemetry_utils.py）
configure_azure_monitor(
    connection_string=connection_string,
    credential=credential
    # sampling_ratio や traces_per_second は未設定
)
```

この場合、Azure Monitor OpenTelemetry Distro のデフォルト動作が適用されます：

- **デフォルトサンプラー**: RateLimitedSampler
- **デフォルトレート**: 5.0 traces/second（秒あたり最大 5 トレース）
- **根拠**: [Microsoft Docs - Azure Monitor OpenTelemetry 構成](https://learn.microsoft.com/azure/azure-monitor/app/opentelemetry-configuration#enable-sampling)

> Starting from 1.8.6, **rate-limited sampling is the default**.
> The default sampler is `Rate Limited Sampler` with the default value of 5.0 traces per second

サンプリング設定は複数レイヤーに存在するため、表示上は「一部スパンだけ見える」「同じ会話でも見え方が変わる」ことがあります。

---

## 本プロジェクトのトレース構成

### スパン階層（acl_off / acl_on の代表）

現在の構造では、`main.py` 側でセッションスパンを開始し、会話ターンごとに `user_chat_turn` を子スパンとして作成しています。

概念図:

```
knowledge-agent-session (root)
  ├─ user_chat_turn
  ├─ user_chat_turn
  └─ user_chat_turn
```

**サンプリングの影響:**

サンプリング（確率ベース・レートベースいずれも）は、実質的に「セッション（root）単位」で動作します。
つまり、同一実行内の複数ターンがまとめて見える/見えない、という結果になります。

### Parent-based Sampling の詳細メカニズム

OpenTelemetry のデフォルト動作は **parent-based sampling** です。これは以下のロジックで動作します：

1. **Root span（親がいないスパン）が開始される**
   - サンプラーが確率的に判定（例: `sampling_ratio=0.05` なら 5% の確率で採択）
   - 採択された場合、`sampled` フラグが `true` に設定される
   - 棄却された場合、`sampled` フラグが `false` に設定される

2. **Child span（親がいるスパン）が開始される**
   - サンプラーは親の `sampled` フラグを**そのまま継承**
   - 独立した確率判定は行わない
   - 親が `sampled=true` なら子も `sampled=true`
   - 親が `sampled=false` なら子も `sampled=false`

3. **結果: "All or Nothing" 動作**
   - 1 つのセッション内のすべてのスパンは、root span の判定結果を共有
   - `knowledge-agent-session` が採択されれば、その中のすべての `user_chat_turn` も採択される
   - `knowledge-agent-session` が棄却されれば、その中のすべての `user_chat_turn` も棄却される

**なぜこの設計なのか？**

- 分散トレースの目的は「1 つのリクエストの全体像」を追跡すること
- 部分的に記録すると因果関係が不明になり、トラブルシューティングが困難になる
- "完全に記録するか、全く記録しないか" の方が実用的

**本プロジェクトへの影響:**

- サンプリングを設定した場合、個々の `user_chat_turn` が独立して採択されるわけではない
- セッション単位でサンプリング判定が行われ、採択されたセッションの中のすべてのターンが記録される
- **デフォルト設定（5.0 traces/second）では**、トラフィックが低い場合はほぼ全量記録され、トラフィックが増えると自動的にレート制限される

---

## サンプリング設定の意味

### デフォルト設定（本プロジェクトの現状）

**重要:** 本プロジェクトでは、`configure_azure_monitor()` で明示的な sampling_ratio または traces_per_second を設定していません。

```python
# 現在の実装
configure_azure_monitor(
    connection_string=connection_string,
    credential=credential
    # sampling_ratio や traces_per_second は未設定
)
```

この場合、**Azure Monitor OpenTelemetry Distro のデフォルト動作**が適用されます：

| 項目                 | デフォルト値       | 説明                                            |
| -------------------- | ------------------ | ----------------------------------------------- |
| **サンプラー**       | RateLimitedSampler | レート制限型サンプラー                          |
| **レート**           | 5.0 traces/second  | 秒あたり最大 5 トレース                         |
| **動作**             | 動的調整           | トラフィック量に応じて自動的に確率を調整        |
| **低トラフィック時** | ほぼ全量記録       | 5 traces/sec 未満の場合は全量                   |
| **高トラフィック時** | レート制限         | 5 traces/sec を超える場合は自動的にサンプリング |

**Microsoft Docs の記載:**

> Starting from 1.8.6, **rate-limited sampling is the default**.
> The default sampler is `Rate Limited Sampler` with the default value of 5.0 traces per second

**参照:** [Azure Monitor OpenTelemetry Configuration - Enable Sampling](https://learn.microsoft.com/azure/azure-monitor/app/opentelemetry-configuration#enable-sampling)

---

### アプリ側: sampling_ratio vs traces_per_second（本番運用時の設定オプション）

Azure Monitor OpenTelemetry Distro (Python) では、デフォルトを変更したい場合に 2 つのサンプリング方式を明示的に設定できます。

#### sampling_ratio（確率ベース）

```python
configure_azure_monitor(
    connection_string=connection_string,
    credential=credential,
    sampling_ratio=0.05,  # 5% に変更
)
```

**動作:**

- 各 root span（トレースの開始点）が独立して確率的にサンプリングされる
- `sampling_ratio=0.05` = 5% = 100 トレースあたり平均 5 トレースが保持される
- **サンプリング決定は root span で行われ、子スパンは親の決定を継承する**（parent-based sampling）

**特徴:**

- シンプルで予測しやすい
- トラフィック量に比例してデータ量も増減
- 低トラフィック時は統計的ブレが大きい（後述）

**数学的背景:**

- 5% サンプリングでは、各トレースは 1/20 の確率で採択される
- Application Insights の `itemCount` フィールドには「このイベント 1 件が何件分を代表するか」が記録される
- サンプリングされた場合、`itemCount=20` となり、「このスパンは実際には 20 件発生したうちの 1 件」を意味する

#### traces_per_second（レートベース）

```python
configure_azure_monitor(
    connection_string=connection_string,
    credential=credential,
    traces_per_second=2.0,  # 秒あたり 2 トレース
)
```

**動作:**

- 単位時間あたりの保持トレース数を直接制御
- トラフィックが増えても、保存レートは一定
- 内部的には動的に確率を調整

**特徴:**

- コスト予測がしやすい（データ量が一定）
- 高トラフィック時は実効サンプリング率が自動で下がる
- 低トラフィック時でもほぼ全量保持される可能性がある

**使い分け:**

- **sampling_ratio**: トラフィックに比例した可視性が欲しい場合
- **traces_per_second**: コスト上限を厳密に管理したい場合（デフォルト）
- **本プロジェクト**: デフォルトの traces_per_second (5.0) を使用中

### APIM 側: sampling_percentage

APIM の Diagnostic サンプリングはアプリ側と**完全に独立した別レイヤー**です。

```hcl
resource "azapi_resource" "foundry_agent_apim_logger" {
  # ...
  sampling_percentage = 50.0  # APIM レイヤーで 50% 保持
}
```

**重要な注意点:**

- アプリ側のサンプリング設定と APIM 側 `sampling_percentage` は**完全に独立**
- 両方でサンプリングが有効な場合、実効保持率は乗算される
  - 例: アプリ側 5%、APIM 側 50% → 実効 2.5%
- APIM サンプリングは APIM 側の span（dependencies テーブル）のみに影響
- アプリ側の span（requests テーブル）とは別レイヤー

**本プロジェクトの現状:**

- **アプリ側**: デフォルト設定（RateLimitedSampler, 5.0 traces/second）
- **APIM 側**: 要確認（infra/modules/gateway/apim-api/\*/\*.tf）

**推奨設定:**

| 環境         | sampling_percentage | 理由                       |
| ------------ | ------------------- | -------------------------- |
| 開発/検証    | 100.0               | 全量記録で問題調査を容易に |
| ステージング | 50.0 〜 100.0       | 本番前の十分な可視性       |
| 本番         | 20.0 〜 50.0        | コストと可視性のバランス   |

**必須設定:**

- `always_log_errors=true` は**必ず有効化**（エラーは常に記録）

---

## 実装ポイント（このリポジトリ）

### 1. propagator で TraceContext 注入（重要な変更点）

**変更前（手動 traceparent 生成）:**

```python
# ❌ 古い実装（非推奨）
def inject_traceparent(request: Request) -> Request:
    current_span = trace.get_current_span()
    context = current_span.get_span_context()

    trace_id = format(context.trace_id, '032x')
    span_id = format(context.span_id, '016x')
    trace_flags = format(context.trace_flags, '02x')

    # 問題: sampled フラグを手動で "01" にハードコード
    traceparent = f"00-{trace_id}-{span_id}-01"
    request.headers['traceparent'] = traceparent
    return request
```

**問題点:**

1. `trace_flags` を無視して常に `"01"`（sampled）をセット
2. 親スパンが `sampled=false` でも、子スパンに `sampled=true` が伝播される
3. サンプリング決定の整合性が壊れる
4. Application Insights でデータ量の期待値がずれる

**変更後（OpenTelemetry propagator 使用）:**

```python
# ✅ 新しい実装（推奨）
from opentelemetry.propagate import inject

def inject_traceparent(request: Request) -> Request:
    # OpenTelemetry の標準 propagator が自動的に:
    # - 現在のコンテキストを取得
    # - trace_id, span_id, trace_flags を正しくフォーマット
    # - sampled フラグを Context から正確に反映
    inject(request.headers)
    return request
```

**メリット:**

1. **sampled フラグの整合性**: Context の `sampled` 状態が正確に伝播される
2. **W3C TraceContext 準拠**: 仕様に完全準拠（version, trace-id, parent-id, trace-flags）
3. **tracestate サポート**: ベンダー固有の追加情報も自動的に処理
4. **保守性向上**: 手動フォーマットによる typo やバグを防止

**W3C TraceContext の構造（参考）:**

```
traceparent: 00-{trace-id}-{parent-id}-{trace-flags}
             ^^  ^^^^^^^^   ^^^^^^^^^   ^^^^^^^^^^^^
             |   |          |           |
             |   |          |           +-- 01=sampled, 00=not sampled
             |   |          +-------------- 現在の span ID (16 桁 hex)
             |   +------------------------- trace ID (32 桁 hex)
             +----------------------------- version (常に "00")
```

**適用箇所:**

本プロジェクトでは以下の 3 ファイルで propagator に変更済み：

- `appcodes/acl_off/modules/telemetry_utils.py`
- `appcodes/acl_on/modules/telemetry_utils.py`
- `appcodes/acl_on_classic-rag/modules/telemetry_utils.py`

### 2. サンプリング設定（Python）

**本プロジェクトの現状:**

現在、`configure_azure_monitor()` では**明示的なサンプリング設定を行っていません**。

```python
# 現在の実装（appcodes/*/modules/telemetry_utils.py）
configure_azure_monitor(
    connection_string=connection_string,
    credential=credential
    # sampling_ratio や traces_per_second は未設定
    # → デフォルトの RateLimitedSampler (5.0 traces/second) が適用される
)
```

**本番運用でサンプリングを調整する場合:**

必要に応じて、以下のように明示的に設定できます。

```python
# オプション1: 確率ベース（例: 5%）
configure_azure_monitor(
    connection_string=connection_string,
    credential=credential,
    sampling_ratio=0.05,
)

# オプション2: レートベース（例: 秒あたり 2 トレース）
configure_azure_monitor(
    connection_string=connection_string,
    credential=credential,
    traces_per_second=2.0,
)
```

#### 環境変数による上書き（重要）

**注意:** コード内で `sampling_ratio` を指定しても、以下の環境変数が設定されていると**環境変数が優先**されます。

| 環境変数                  | 説明             | 例                           |
| ------------------------- | ---------------- | ---------------------------- |
| `OTEL_TRACES_SAMPLER`     | サンプラーの種類 | `microsoft.fixed_percentage` |
| `OTEL_TRACES_SAMPLER_ARG` | サンプラーの引数 | `0.1`（10%）                 |

**確認方法:**

```bash
# 現在の環境変数を確認
env | grep OTEL_TRACES

# 設定されている場合は削除
unset OTEL_TRACES_SAMPLER
unset OTEL_TRACES_SAMPLER_ARG
```

**優先順位:**

1. **環境変数** `OTEL_TRACES_SAMPLER` / `OTEL_TRACES_SAMPLER_ARG`（最優先）
2. **コード** `configure_azure_monitor(sampling_ratio=...)` または `configure_azure_monitor(traces_per_second=...)`
3. **デフォルト**: RateLimitedSampler (5.0 traces/second)

**推奨プラクティス:**

- 開発環境: デフォルト設定（5.0 traces/second）のまま使用、または全量記録 (`sampling_ratio=1.0`)
- ステージング環境: 本番想定値をコードで設定（バージョン管理しやすい）
- 本番環境: 環境変数で設定（デプロイ時に柔軟に変更可能）

---

## 検証手順（Application Insights / KQL）

### itemCount フィールドの詳細解説

Application Insights では、サンプリングされたイベントに `itemCount` フィールドが付与されます。

**itemCount の意味:**

- **定義**: このイベント 1 件が実際には何件のイベントを代表しているか
- **サンプリングなし**: `itemCount=1`（このイベントは 1 件分）
- **確率ベースサンプリング**: `itemCount = 1 / sampling_ratio`
- **レートベースサンプリング**: `itemCount` は動的に変化（トラフィック量に応じて）

**数学的背景（確率ベースサンプリングの場合）:**

| sampling_ratio | 保持確率 | itemCount | 意味                             |
| -------------- | -------- | --------- | -------------------------------- |
| 1.0            | 100%     | 1         | すべて記録                       |
| 0.5            | 50%      | 2         | 記録された 1 件は実際の 2 件分   |
| 0.1            | 10%      | 10        | 記録された 1 件は実際の 10 件分  |
| 0.05           | 5%       | 20        | 記録された 1 件は実際の 20 件分  |
| 0.01           | 1%       | 100       | 記録された 1 件は実際の 100 件分 |

**本プロジェクトの現状（RateLimitedSampler 使用時）:**

- デフォルト設定（5.0 traces/second）では、トラフィックが低い場合は `itemCount=1`（全量記録）
- トラフィックが高い場合は、動的に `itemCount` が増加（レート制限が発動）
- 例: 秒あたり 10 トレース発生 → 5 トレース記録 → `itemCount≈2`

**重要な性質:**

```kusto
// 実際の発生件数を推定
let ObservedCount = count();          // Application Insights に記録された件数
let EstimatedOriginal = sum(itemCount); // 実際に発生した推定件数

// 例: デフォルト設定（5.0 traces/second）
// - 低トラフィック時: itemCount=1（ほぼ全量記録）
// - 高トラフィック時: itemCount が動的に増加
```

**実効保持率の計算:**

```kusto
RetainedPercentage = 100.0 × ObservedCount / EstimatedOriginal
                   = 100.0 × count() / sum(itemCount)
```

### 手順1: user_chat_turn がどのテーブルに入っているか確認

```kusto
union withsource=Table requests, dependencies
| where timestamp > ago(1h)
| where name == "user_chat_turn"
| summarize Rows=count() by Table
```

**期待結果:**

- `requests` テーブルに表示される（アプリ側で作成したスパン）
- `dependencies` テーブルには表示されない（外部呼び出しではないため）

### 手順2: user_chat_turn の実効 retained 率を確認

```kusto
union requests, dependencies
| where timestamp > ago(1h)
| where name == "user_chat_turn"
| summarize Observed=count(), EstimatedOriginal=sum(itemCount), AvgItemCount=avg(itemCount)
| extend RetainedPercentage = 100.0 * todouble(Observed) / todouble(EstimatedOriginal)
```

**結果の読み方:**

| フィールド           | 意味               | デフォルト設定の期待値                                |
| -------------------- | ------------------ | ----------------------------------------------------- |
| `Observed`           | 記録されたスパン数 | トラフィック依存                                      |
| `EstimatedOriginal`  | 実際の発生推定数   | トラフィック依存                                      |
| `AvgItemCount`       | itemCount の平均   | 低トラフィック時: 1、高トラフィック時: 2〜            |
| `RetainedPercentage` | 実効保持率         | 低トラフィック時: ≈100%、高トラフィック時: 動的に低下 |

**本プロジェクトの場合（デフォルト設定: 5.0 traces/second）:**

- **低トラフィック時**（5 traces/sec 未満）:
  - `AvgItemCount` ≈ 1（ほぼ全量記録）
  - `RetainedPercentage` ≈ 100%
- **高トラフィック時**（例: 10 traces/sec）:
  - `AvgItemCount` ≈ 2（半分をサンプリング）
  - `RetainedPercentage` ≈ 50%

**確率ベースサンプリング使用時の例（sampling_ratio=0.05）:**

- `AvgItemCount` ≈ 20（= 1/0.05）
- `RetainedPercentage` ≈ 5.0%

**注意点:**

- `AvgItemCount` は理論値に近づくが、完全一致しない場合がある
- 理由: parent-based sampling により、セッション単位で判定されるため
- セッション内のターン数が異なると、ターン単位の itemCount にバラつきが出る

### 手順3: セッションスパン単位で判定（推奨）

```kusto
union requests, dependencies, traces, exceptions
| where timestamp > ago(1h)
| where name in ("knowledge-agent-session", "knowledge-classic-rag-session")
| summarize Observed=count(), EstimatedOriginal=sum(itemCount), AvgItemCount=avg(itemCount) by name
| extend RetainedPercentage = 100.0 * todouble(Observed) / todouble(EstimatedOriginal)
```

**なぜセッション単位が推奨か？**

- parent-based sampling の判定単位が root span（セッション）
- `user_chat_turn` は子スパンなので、セッション単位で集計した方が正確
- セッション単位の `RetainedPercentage` が最も実際のサンプリング率に近い値になる

### 統計的検証の詳細: サンプリング設定時の注意点

**重要:** 本プロジェクトは現在デフォルト設定（RateLimitedSampler, 5.0 traces/second）を使用しています。
以下の説明は、**確率ベースサンプリング（sampling_ratio）を設定した場合**の検証方法です。

#### 確率ベースサンプリングを使用する場合の統計的必要サンプル数

`sampling_ratio=0.05`（5%）のような確率ベースサンプリングを設定した場合、各セッションは独立して 5% の確率で採択されます。

**問題例: sampling_ratio=0.05 なのに 3/3 で全部見える**

これは**統計的に正常**です。理由を説明します。

**3 回実行した場合の確率分布:**

| 結果     | 確率                       | 説明           |
| -------- | -------------------------- | -------------- |
| 0/3 採択 | (0.95)³ = **85.7%**        | 全部見えない   |
| 1/3 採択 | 3 × 0.05 × (0.95)² = 13.5% | 1 件だけ見える |
| 2/3 採択 | 3 × (0.05)² × 0.95 = 0.7%  | 2 件見える     |
| 3/3 採択 | (0.05)³ = **0.01%**        | 全部見える     |

**結論:**

- 3 回の試行では、**85.7% の確率で何も記録されない**
- 3/3 で全部見える確率は 0.01%（1万回に1回）だが、1/3 や 2/3 は十分あり得る
- 「全部見える」「全然見えない」のどちらも異常ではない

#### 必要なサンプル数

信頼できる検証には、**統計的に十分な試行回数**が必要です。

**目安:**

| 試行回数 | 期待採択数 | 標準偏差 | 95% 信頼区間 |
| -------- | ---------- | -------- | ------------ |
| 10       | 0.5        | 0.7      | 0 〜 2       |
| 20       | 1.0        | 1.0      | 0 〜 3       |
| 50       | 2.5        | 1.5      | 0 〜 6       |
| 100      | 5.0        | 2.2      | 1 〜 9       |
| 200      | 10.0       | 3.1      | 4 〜 16      |
| 500      | 25.0       | 4.9      | 15 〜 35     |

**推奨:**

- **最低 50 セッション**: 統計的なブレが大きいが、おおよその傾向は見える
- **100 セッション以上**: 信頼できる検証が可能
- **200 セッション以上**: 精度の高い検証が可能

**検証例:**

```bash
# 100 回実行（sampling_ratio=0.05 の場合）
for i in {1..100}; do
  python appcodes/acl_on/main.py
  sleep 1
done

# 30 分後に KQL で確認
# 期待: Observed=約 5, RetainedPercentage=約 5.0%
```

---

## トラブルシューティング

### 症状1: デフォルト設定なのにトレースが記録されない

**本プロジェクトの現状（デフォルト設定）:**

デフォルト設定（RateLimitedSampler, 5.0 traces/second）では、**低トラフィック時はほぼ全量記録**されます。

**原因候補:**

1. **環境変数でサンプリングが設定されている**（最も可能性が高い）

   ```bash
   # 確認
   echo "OTEL_TRACES_SAMPLER: $OTEL_TRACES_SAMPLER"
   echo "OTEL_TRACES_SAMPLER_ARG: $OTEL_TRACES_SAMPLER_ARG"
   ```

2. **Application Insights への接続問題**
   - 接続文字列が誤っている
   - 認証情報が不正
   - ネットワーク接続の問題

3. **テレメトリの初期化タイミング**
   - `configure_azure_monitor()` が呼ばれる前にスパンが開始されている

**対処:**

```bash
# 環境変数をクリア
unset OTEL_TRACES_SAMPLER
unset OTEL_TRACES_SAMPLER_ARG

# 再実行
python appcodes/acl_on/main.py
```

```kusto
// Application Insights で確認
requests
| where timestamp > ago(1h)
| where name in ("knowledge-agent-session", "knowledge-classic-rag-session")
| summarize count()
```

---

### 症状2: 確率ベースサンプリング設定時に「3/3 で全部見える」

**注意:** このセクションは `sampling_ratio` を明示的に設定した場合の症状です。

**原因候補:**

1. **統計的な偶然**（最も可能性が高い）
   - 3 回の試行では統計的に不十分（前述の確率計算参照）
   - sampling_ratio=0.05 でも、1/3 や 2/3 が見える確率は合計 14.2% あり、十分起こり得る

2. **Parent-based sampling の特性**
   - root span（セッション）が採択され、その子ターンがまとめて記録された
   - セッション単位で "all or nothing" になるため、見えるときは全部見える

3. **APIM 側テレメトリの混在**
   - APIM からの `dependencies` が別レイヤーで記録されている可能性
   - `requests` テーブルだけに絞って確認

**対処:**

```kusto
// ✅ 正しい検証: セッション単位で 50 件以上
union requests
| where timestamp > ago(1h)
| where name in ("knowledge-agent-session", "knowledge-classic-rag-session")
| summarize Observed=count(), EstimatedOriginal=sum(itemCount)
| extend RetainedPercentage = 100.0 * todouble(Observed) / todouble(EstimatedOriginal)
```

**期待結果（sampling_ratio=0.05 の場合）:**

- 50 〜 100 セッション実行後: `RetainedPercentage` が 3% 〜 7% の範囲
- 200 セッション実行後: `RetainedPercentage` が 4% 〜 6% の範囲

### 症状3: 設定値と挙動が一致しない

**原因候補:**

1. **環境変数の上書き**（最も頻繁）
   - `OTEL_TRACES_SAMPLER` / `OTEL_TRACES_SAMPLER_ARG` がコードより優先される

**確認手順:**

```bash
# 環境変数を確認
echo "OTEL_TRACES_SAMPLER: $OTEL_TRACES_SAMPLER"
echo "OTEL_TRACES_SAMPLER_ARG: $OTEL_TRACES_SAMPLER_ARG"

# 設定されている場合の例:
# OTEL_TRACES_SAMPLER: parentbased_traceidratio
# OTEL_TRACES_SAMPLER_ARG: 0.1
# → コード内の設定が無視され、10% サンプリングになる
```

**対処:**

```bash
# 環境変数を削除
unset OTEL_TRACES_SAMPLER
unset OTEL_TRACES_SAMPLER_ARG

# または明示的に設定
export OTEL_TRACES_SAMPLER=microsoft.fixed_percentage
export OTEL_TRACES_SAMPLER_ARG=0.05

# 再実行
python appcodes/acl_on/main.py
```

2. **複数バージョンの OpenTelemetry パッケージ**
   - `azure-monitor-opentelemetry` と手動インストールした `opentelemetry-sdk` が競合

**確認:**

```bash
pip list | grep opentelemetry
pip list | grep azure-monitor
```

**対処:**

```bash
# 不要なパッケージを削除
pip uninstall opentelemetry-sdk opentelemetry-api

# Azure Monitor Distro だけを再インストール
pip install --upgrade azure-monitor-opentelemetry
```

---

### 症状4: 確率ベースサンプリング使用時に「ほぼ何も出ない」

**注意:** このセクションは `sampling_ratio` を明示的に設定した場合の症状です（例: sampling_ratio=0.05）。

**原因候補:**

1. **母数不足による統計ブレ**
   - sampling_ratio=0.05 で 10 回実行すると、0 件採択される確率は 60% ある（正常）
2. **時間窓の設定ミス**
   - `ago(1h)` で過去 1 時間を見ているが、実行は 5 分前
   - データの取り込みに数分のラグがある

**対処:**

```kusto
// ✅ 広めの時間窓で確認
union requests
| where timestamp > ago(6h)  // 6 時間に拡大
| where name == "knowledge-agent-session"
| summarize Observed=count(), EstimatedOriginal=sum(itemCount)
| extend RetainedPercentage = 100.0 * todouble(Observed) / todouble(EstimatedOriginal)
```

3. **APIM 側のサンプリングとの乗算効果**
   - アプリ側 5%、APIM 側 50% → 実効 2.5%
   - さらに見えにくくなる

**確認:**

```kusto
// アプリ側とゲートウェイ側を分けて確認
requests  // アプリ側
| where timestamp > ago(1h)
| where name == "knowledge-agent-session"
| summarize count()

dependencies  // APIM 側
| where timestamp > ago(1h)
| where name contains "foundry"
| summarize count()
```

---

### 症状5: itemCount が常に 1 になる

**原因:**

- サンプリングが実際には無効になっている、または全量記録されている
- **本プロジェクトの現状**: デフォルト設定では低トラフィック時に `itemCount=1` は正常

**確認:**

```kusto
requests
| where timestamp > ago(1h)
| where name == "knowledge-agent-session"
| summarize min(itemCount), max(itemCount), avg(itemCount)
```

**判定:**

| 状況                            | avg(itemCount) | 原因                                     |
| ------------------------------- | -------------- | ---------------------------------------- |
| デフォルト設定 + 低トラフィック | 1              | 正常（5 traces/sec 未満なので全量記録）  |
| デフォルト設定 + 高トラフィック | 1〜            | 正常（トラフィック量に応じて動的に変化） |
| sampling_ratio=0.05 設定時      | ≈ 20           | 正常（確率ベースサンプリング）           |
| sampling_ratio=0.05 設定時      | 1              | 異常（環境変数で上書きされている可能性） |

**対処:**

- デフォルト設定で `itemCount=1`: 正常動作
- 確率ベースサンプリング設定時に `itemCount=1`: 環境変数を確認（症状3 参照）

---

## 本番運用の推奨値と調整方針

**重要:** 以下のセクションは、**本番運用でサンプリング設定を調整する場合**のガイドラインです。
本プロジェクトは現在デフォルト設定（RateLimitedSampler, 5.0 traces/second）を使用しています。

### デフォルト設定の評価

まず、デフォルト設定（5.0 traces/second）が要件に合っているか評価します。

**デフォルト設定の特性:**

| トラフィック量     | 動作                     | データ量               |
| ------------------ | ------------------------ | ---------------------- |
| 〜 5 traces/sec    | ほぼ全量記録             | トラフィックに比例     |
| 5 〜 10 traces/sec | 部分的にサンプリング開始 | 約 5 traces/sec に制限 |
| 10 traces/sec 〜   | レート制限が有効         | 約 5 traces/sec で一定 |

**評価基準:**

- ✅ **デフォルトのまま使用**: トラフィックが少なく（月間 10万セッション未満）、コストが問題にならない場合
- ⚠️ **sampling_ratio に変更**: トラフィックに比例した可視性が必要な場合
- ⚠️ **traces_per_second を調整**: デフォルトの 5.0 が多すぎる/少なすぎる場合

---

### トラフィック量別の推奨 sampling_ratio（確率ベースに変更する場合）

本番環境のサンプリング率は、**月間トラフィック量**と**可観測性要件**のバランスで決定します。

#### 目安表

| 月間セッション数       | 推奨 sampling_ratio | 月間記録セッション数 | 備考             |
| ---------------------- | ------------------- | -------------------- | ---------------- |
| 〜 10,000              | 1.0（100%）         | 10,000               | 全量記録可能     |
| 10,000 〜 50,000       | 0.5（50%）          | 5,000 〜 25,000      | 高可視性維持     |
| 50,000 〜 100,000      | 0.2（20%）          | 10,000 〜 20,000     | バランス型       |
| 100,000 〜 500,000     | 0.1（10%）          | 10,000 〜 50,000     | 標準的な本番設定 |
| 500,000 〜 1,000,000   | 0.05（5%）          | 25,000 〜 50,000     | コスト重視       |
| 1,000,000 〜 5,000,000 | 0.02（2%）          | 20,000 〜 100,000    | 大規模運用       |
| 5,000,000 〜           | 0.01（1%）          | 50,000 〜            | 超大規模         |

**traces_per_second を使う場合:**

月間セッション数に関わらず、**一定のデータ量**を維持したい場合は `traces_per_second` を使用します。

```python
# 例: 秒あたり 2 トレースに制限
configure_azure_monitor(
    connection_string=connection_string,
    credential=credential,
    traces_per_second=2.0,
)

# 月間データ量の計算:
# 2 traces/sec × 3600 sec/hour × 24 hours/day × 30 days = 5,184,000 traces/month
```

### 初期設定の推奨手順

**ステップ 1: 開発/検証環境でデフォルト設定を使用**

```python
# 開発環境: デフォルト設定（推奨）
configure_azure_monitor(
    connection_string=connection_string,
    credential=credential
    # サンプリング設定なし → RateLimitedSampler (5.0 traces/second) が適用
)
```

**メリット:**

- 低トラフィック時は全量記録されるため、開発中のデバッグが容易
- 設定が不要で、シンプル

**必要に応じて全量記録に変更:**

```python
# 開発環境: 全量記録（オプション）
configure_azure_monitor(
    connection_string=connection_string,
    credential=credential,
    sampling_ratio=1.0,  # 全量
)
```

---

**ステップ 2: ステージング環境で本番想定値をテスト**

本番環境のトラフィック予測に基づいて、サンプリング設定を決定します。

**オプション A: デフォルト設定をそのまま使用（推奨）**

```python
# ステージング環境: デフォルト設定
configure_azure_monitor(
    connection_string=connection_string,
    credential=credential
    # デフォルトの RateLimitedSampler (5.0 traces/second)
)
```

**オプション B: 確率ベースサンプリングに変更**

```python
# ステージング環境: sampling_ratio=0.1（10%）
configure_azure_monitor(
    connection_string=connection_string,
    credential=credential,
    sampling_ratio=0.1,
)
```

- 100 セッション以上実行して検証
- KQL で `RetainedPercentage` が 9% 〜 11% の範囲に入ることを確認

---

**ステップ 3: 本番環境で運用開始**

**オプション A: デフォルト設定で開始（推奨）**

```python
# 本番環境: デフォルト設定
configure_azure_monitor(
    connection_string=connection_string,
    credential=credential
    # デフォルトの RateLimitedSampler (5.0 traces/second)
)
```

- 1 週間〜1 ヶ月運用してデータ量とコストを確認
- トラフィックが低い場合はほぼ全量記録され、高い場合は自動的にレート制限される
- コストが許容範囲なら、このまま継続

**オプション B: 確率ベースサンプリングで開始**

```python
# 本番環境初期: sampling_ratio=0.2（20%）から開始
configure_azure_monitor(
    connection_string=connection_string,
    credential=credential,
    sampling_ratio=0.2,
)
```

- 1 週間運用してデータ量とコストを確認
- 可観測性が十分なら、段階的に下げる（0.2 → 0.1 → 0.05）
- 不足なら上げる（0.2 → 0.5）

### APIM 側サンプリングの設定

APIM 側の `sampling_percentage` は、アプリ側とは**独立して**設定します。

**推奨設定:**

| 環境         | sampling_percentage | 理由                       |
| ------------ | ------------------- | -------------------------- |
| 開発         | 100.0               | 全量記録で問題調査を容易に |
| ステージング | 50.0 〜 100.0       | 本番前の十分な可視性       |
| 本番         | 20.0 〜 50.0        | コストと可視性のバランス   |

**重要:** `always_log_errors=true` は**必ず有効化**

```hcl
resource "azapi_resource" "foundry_agent_apim_logger" {
  # ...
  body = jsonencode({
    properties = {
      # ...
      sampling = {
        sampling_type = "fixed"
        percentage    = 50.0  # 本番: 20.0 〜 50.0
      }
      always_log_errors = true  # ✅ 必須
    }
  })
}
```

### 調整判断のための KQL ダッシュボード

本番運用では、以下の KQL クエリを定期的に実行して調整を判断します。

#### クエリ 1: 日次データ量トレンド

```kusto
union requests, dependencies
| where timestamp > ago(30d)
| where name in ("knowledge-agent-session", "knowledge-classic-rag-session", "user_chat_turn")
| summarize
    ObservedCount=count(),
    EstimatedOriginal=sum(itemCount),
    DataVolumeMB=sum(estimate_data_size(*)) / 1048576.0
    by bin(timestamp, 1d), name
| extend RetainedPercentage = 100.0 * todouble(ObservedCount) / todouble(EstimatedOriginal)
| project timestamp, name, ObservedCount, EstimatedOriginal, RetainedPercentage, DataVolumeMB
| order by timestamp desc
```

#### クエリ 2: 月次コスト推定

```kusto
union requests, dependencies
| where timestamp > ago(30d)
| where name in ("knowledge-agent-session", "knowledge-classic-rag-session")
| summarize
    TotalDataSizeGB=sum(estimate_data_size(*)) / 1073741824.0,
    TotalEvents=sum(itemCount)
| extend
    EstimatedMonthlyCostUSD = TotalDataSizeGB * 2.88,  // Application Insights 価格（例: $2.88/GB）
    EventsPerDay = TotalEvents / 30.0
| project TotalDataSizeGB, EstimatedMonthlyCostUSD, TotalEvents, EventsPerDay
```

### 調整方針のフローチャート

```
[現在の状態を確認]
       ↓
┌─────────────────────────┐
│ データ量 or コストが    │
│ 想定を超えている？      │
└─────────────────────────┘
       ↓ Yes                   ↓ No
[sampling_ratio を下げる]  ┌─────────────────────────┐
   0.2 → 0.1               │ トラブルシューティング  │
   0.1 → 0.05              │ に支障がある？          │
   0.05 → 0.02             └─────────────────────────┘
       ↓                          ↓ Yes
[1 週間様子見]            [sampling_ratio を上げる]
       ↓                      0.05 → 0.1
[再評価]                     0.1 → 0.2
                                   ↓
                            [1 週間様子見]
                                   ↓
                            [再評価]
```

### 特殊ケース: エラートレースの優先記録

エラーが発生したトレースを**優先的に記録**したい場合は、カスタムサンプラーを実装します。

```python
from opentelemetry.sdk.trace.sampling import ParentBasedTraceIdRatio, ALWAYS_ON
from opentelemetry.sdk.trace import TracerProvider, sampling

# エラー時は必ず記録するカスタムサンプラー
class ErrorAwareSampler(sampling.Sampler):
    def __init__(self, base_sampler):
        self.base_sampler = base_sampler

    def should_sample(self, parent_context, trace_id, name, kind, attributes, links, trace_state):
        # エラーまたは例外がある場合は必ず記録
        if attributes and ('error' in attributes or 'exception' in attributes):
            return sampling.SamplingResult(sampling.Decision.RECORD_AND_SAMPLE, attributes, trace_state)

        # 通常は base_sampler に委譲
        return self.base_sampler.should_sample(parent_context, trace_id, name, kind, attributes, links, trace_state)

# 使用例
base_sampler = ParentBasedTraceIdRatio(0.05)  # 5% base
error_aware_sampler = ErrorAwareSampler(base_sampler)

# TracerProvider に設定
tracer_provider = TracerProvider(sampler=error_aware_sampler)
```

**注意:** Azure Monitor Distro を使う場合、カスタムサンプラーの適用は制限される場合があります。
また、デフォルトで APIM の `always_log_errors=true` が有効なため、エラートレースは既に優先記録されます。

---

### モニタリングアラートの設定

Application Insights でアラートを設定し、テレメトリ収集の異常を検知します。

#### アラート 1: トレース収集の停止検知（デフォルト設定用）

```kusto
// アラートクエリ: 過去 1 時間にトレースが 1 件も記録されていない
union requests
| where timestamp > ago(1h)
| where name in ("knowledge-agent-session", "knowledge-classic-rag-session")
| summarize Count=count()
| where Count == 0
```

**推奨アラート条件:**

- トレースが 0 件の状態が 1 時間以上継続
- アクション: 開発者に通知、テレメトリ設定を確認

---

#### アラート 2: 確率ベースサンプリング使用時の異常検知

**注意:** 以下は `sampling_ratio` を明示的に設定した場合のアラートです。

```kusto
// アラートクエリ: RetainedPercentage が期待値から大きく外れた
union requests
| where timestamp > ago(1h)
| where name == "knowledge-agent-session"
| summarize Observed=count(), EstimatedOriginal=sum(itemCount)
| extend RetainedPercentage = 100.0 * todouble(Observed) / todouble(EstimatedOriginal)
| where RetainedPercentage < 3.0 or RetainedPercentage > 7.0  // sampling_ratio=0.05 の場合
```

**推奨アラート条件:**

- `RetainedPercentage` が期待値の ±2% を超える状態が 1 時間以上継続
- 例: `sampling_ratio=0.05` の場合、3% 未満または 7% 超
- アクション: 環境変数設定を確認、サンプラー設定を検証

---

以上。
