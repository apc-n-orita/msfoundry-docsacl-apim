# Application Insights Profiler / Snapshot Debugger

## 概要

Application Insights のトレース・ログだけでは原因が特定できない障害（パフォーマンス劣化・本番固有の例外）を調査するための高度なデバッグ機能です。

> **基本的な監視（メトリクス・分散トレース・例外ログ・アラート）はこれらのツールなしで利用できます。**  
> パフォーマンス問題や原因不明の例外が継続的に発生した場合の次の手として活用してください。

---

## Application Insights Profiler

### 用途と利用シナリオ

**実運用のパフォーマンスボトルネックをメソッド単位で特定**するツールです。

典型的な利用シナリオ:

- Foundry Agent への API 呼び出しレイテンシが高い原因を調査する
- Functions の特定のエンドポイントで応答が遅い場合のホットパスを特定する
- OBO フローのどのステップでボトルネックが発生しているかを可視化する

### 取得できる情報

| データ         | 内容                                               |
| -------------- | -------------------------------------------------- |
| コールスタック | メソッドごとのミリ秒単位の実行時間                 |
| ホットパス     | 最も時間を消費しているコードパス（赤色ハイライト） |
| `CPU_TIME`     | CPU 実行時間                                       |
| `BLOCKED_TIME` | 同期オブジェクト待機時間                           |
| `AWAIT`        | 非同期処理（外部 API / DB クエリ）の待機時間       |

### 有効化方法（Azure Functions）

Function App の環境変数に以下を追加します。

```bash
az functionapp config appsettings set \
  --name <func-app-name> \
  --resource-group <rg-name> \
  --settings \
    APPINSIGHTS_PROFILERFEATURE_VERSION="1.0.0" \
    DiagnosticServices_EXTENSION_VERSION="~3"
```

### 自動トリガー

| トリガー     | 条件                      | 収集時間 |
| ------------ | ------------------------- | -------- |
| **Sampling** | 1 時間に 1 回（ランダム） | 2 分間   |
| **CPU**      | CPU 使用率 80% 超         | 30 秒間  |
| **Memory**   | メモリ使用率 80% 超       | 30 秒間  |

**オンデマンド実行**: `Application Insights → Performance → Profiler → Profile Now`  
→ 約 2 分後にトレースが記録され、5〜10 分後に結果が表示されます。

---

## Snapshot Debugger

### 用途と利用シナリオ

**実運用でのみ発生する例外の変数値を事後に確認**するツールです。

典型的な利用シナリオ:

- OBO フローで `acquire_token_on_behalf_of()` が失敗するが開発環境では再現しない
- JWT デコード時に KeyError が発生しているが、どの値が欠落しているか不明
- 本番の特定ユーザーのみリクエストが失敗する原因を調査する

### 取得できる情報

| データ                           | 取得可否 |
| -------------------------------- | -------- |
| 例外発生時のコールスタック       | ✅       |
| 各フレームのローカル変数の値     | ✅       |
| パラメータの値                   | ✅       |
| 例外メッセージとスタックトレース | ✅       |
| スナップショット以前の実行履歴   | ❌       |
| データベースの状態               | ❌       |

### 有効化方法（Azure Functions）

`host.json` に以下を追加して Function App を再デプロイします。

```json
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "snapshotConfiguration": {
        "isEnabled": true
      }
    }
  }
}
```

### 制限事項

- 1 日最大 50 スナップショット / 10 分に 1 スナップショット
- データ保持期間: 15 日間
- Consumption プランは非対応（Basic 以上が必要）
- 同じ例外が **2 回発生した時点**でスナップショットが作成される

---

## Private Link 環境（AMPLS）での BYOS 設定

Azure Private Link を使用している環境では、Profiler / Snapshot Debugger が収集したデータを自分のストレージアカウントに保存する **BYOS（Bring Your Own Storage）** 設定が必要です。

詳細な設定手順（Terraform コード・CLI コマンド・検証クエリを含む）は以下を参照してください。

→ [Application Insights Profiler と Snapshot Debugger 設定ガイド](../../knowleage/Application_Insights_Profiler_Snapshot_Debugger_Guide.md)

---

## まとめ：使い分けの指針

| 状況                                 | 推奨ツール                                       |
| ------------------------------------ | ------------------------------------------------ |
| 特定エンドポイントのレイテンシが高い | **Profiler** → ホットパスを特定                  |
| 本番固有の例外で変数値を確認したい   | **Snapshot Debugger** → 変数インスペクション     |
| 通常のメトリクス・エラー監視         | Application Insights の標準機能（Profiler 不要） |
| 分散トレースで根本原因がわかった     | 標準のスパン属性で十分                           |

---

## 前のドキュメント

- [Microsoft Foundry のさらなるセキュリティ強化](./04_advanced_security.md)

---

<!--
  最後まで読んでくれた方へ
-->

[最後まで読んでくれた方へ](../extra/spirituality_in_it.md)
