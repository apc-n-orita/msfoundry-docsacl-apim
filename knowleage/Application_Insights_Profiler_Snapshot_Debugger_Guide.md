# Application Insights Profiler と Snapshot Debugger 設定ガイド

## 目次

1. [概要](#概要)
2. [Application Insights Profiler](#application-insights-profiler)
3. [Snapshot Debugger](#snapshot-debugger)
4. [AMPLS環境でのBYOS設定](#ampls環境でのbyos設定)
5. [実装手順](#実装手順)
6. [トラブルシューティング](#トラブルシューティング)

---

## 概要

### これらのツールは必須か？

**結論: オプション機能**

Application Insights Profiler と Snapshot Debugger は高度なデバッグ機能であり、**基本的な監視には不要**です。

#### ✅ これらのツールがなくても利用できる機能

- メトリクス収集（CPU、メモリ、リクエスト数など）
- トレース・ログ収集
- 分散トレーシング（依存関係マップ）
- **例外ログの自動記録**（スタックトレースを含む）
- カスタムイベント・メトリクス
- Application Map（アプリケーションマップ）
- Live Metrics（ライブメトリクス）
- アラート・ダッシュボード

#### ❌ これらのツールがないと利用できない高度な機能

**Profiler なし:**

- 詳細なパフォーマンス分析（メソッド単位の実行時間）
- Code Optimizations（AI駆動の最適化提案）

**Snapshot Debugger なし:**

- 例外発生時の変数値の確認
- メモリスナップショット

---

## Application Insights Profiler

### 用途

**本番環境のパフォーマンスボトルネックを特定するためのツール**

#### 主な機能

1. **ホットパス分析** - 最も時間を消費しているメソッドを特定
2. **コールスタック可視化** - メソッド呼び出しのミリ秒単位の詳細表示
3. **自動トリガー**:
   - **Sampling**: 1時間に1回、2分間（ランダムサンプリング）
   - **CPU**: CPU使用率80%超で自動収集（30秒間）
   - **Memory**: メモリ使用率80%超で自動収集（30秒間）

#### 使用例

- Web APIの応答が遅いエンドポイントの調査
- データベースクエリ、外部API呼び出しの待機時間分析
- メモリリークやオブジェクト割り当ての問題特定

### Azure Functions での有効化手順

#### ステップ1: アプリケーション設定の追加

Function App に以下の環境変数を追加：

```bash
# Azure Portal: Function App → 設定 → 環境変数 → 新しいアプリケーション設定
```

| 設定名                                  | 値                               |
| --------------------------------------- | -------------------------------- |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Application Insightsの接続文字列 |
| `APPINSIGHTS_PROFILERFEATURE_VERSION`   | `1.0.0`                          |
| `DiagnosticServices_EXTENSION_VERSION`  | `~3`                             |

#### Terraform での実装例

```hcl
resource "azurerm_linux_function_app" "func" {
  name                = "func-${var.environment}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  app_settings = {
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.ai.connection_string
    APPINSIGHTS_PROFILERFEATURE_VERSION   = "1.0.0"
    DiagnosticServices_EXTENSION_VERSION  = "~3"
  }
}
```

#### ステップ2: トリガー設定

Azure Portal でトリガーを設定：

```
Application Insights → Performance → Profiler → Triggers
```

**設定可能なトリガー:**

1. **Sampling トリガー**
   - サンプルレート: Normal（5%）/ High（50%）/ Maximum（75%）
   - 収集時間: デフォルト30秒
   - クールダウン: 次回実行までの待機時間

2. **CPU トリガー**
   - CPU閾値: 0-100%（デフォルト80%）
   - 収集時間: デフォルト30秒
   - クールダウン: デフォルト設定あり

3. **Memory トリガー**
   - メモリ閾値: 0-100%（デフォルト80%）
   - 収集時間: デフォルト30秒
   - クールダウン: デフォルト設定あり

### プロファイリングの実行

#### 方法1: オンデマンドプロファイリング（Profile Now）

即座にプロファイリングを開始：

```
Application Insights → Performance → Profiler → 「Profile Now」ボタン
```

- **実行時間**: 約2分間
- **結果表示**: 5-10分後
- **対象**: この Application Insights に接続されているすべてのエージェント

#### 方法2: 自動トリガー

設定した条件（CPU、Memory、Sampling）に基づいて自動実行。

### プロファイリング結果の確認

#### Performance ペインから確認

```
1. Application Insights → Performance
2. オペレーション名を選択
3. 「Profiler traces」をクリック
4. トレースを選択してコールスタックを表示
```

#### Recent profiling sessions から確認

```
Application Insights → Performance → Profiler → Recent profiling sessions
```

**表示される情報:**

| 項目             | 内容                                            |
| ---------------- | ----------------------------------------------- |
| Triggered by     | トリガー方法（Sampling/CPU/Memory/Profile now） |
| App Name         | プロファイルされたアプリケーション名            |
| Machine Instance | 実行されたマシンのインスタンス名                |
| Timestamp        | プロファイル取得日時                            |
| CPU %            | プロファイリング中のCPU使用率                   |
| Memory %         | プロファイリング中のメモリ使用率                |

### トレースデータの読み方

#### 確認できる情報

1. **コールスタック全体** - メソッドごとの実行時間（ミリ秒単位）
2. **ホットパス** - 最も時間を消費しているコードパス（赤色でハイライト）
3. **時間の内訳**:
   - `CPU_TIME`: CPU実行時間
   - `BLOCKED_TIME`: リソース待機時間（同期オブジェクト、スレッド）
   - `AWAIT`: 非同期処理の待機時間
   - `Network time`: ネットワーク操作
   - `Disk time`: ディスクI/O操作

#### パフォーマンス問題の分析

```
高いCPU_TIME → CPU処理の最適化が必要
高いBLOCKED_TIME → 同期処理の見直し、非同期化検討
高いAWAIT → 外部API、DBクエリの最適化
```

### コストと制限

- **ストレージコスト**: 無料（15日後自動削除）
- **オーバーヘッド**: 5-15%のCPU/メモリ
- **収集頻度**: デフォルトで1時間に2分（Sampling）
- **データ保持期間**: 15日間

---

## Snapshot Debugger

### 用途

**本番環境で発生した例外の詳細調査**

#### 主な機能

1. **自動スナップショット収集** - 例外発生時に自動でメモリスナップショットを取得
2. **変数インスペクション** - 例外発生時点のローカル変数、パラメータを確認
3. **コールスタック保存** - 例外に至るまでの完全な呼び出し履歴

#### 使用例

- 本番環境でのみ発生する例外の原因調査
- ユーザーから報告されたエラーの詳細分析
- 開発環境では再現できない問題のデバッグ

### 動作の仕組み

1. **例外発生**: アプリケーションで例外がスローされる
2. **カウント**: 同じ例外が発生するたびにカウンターが増加
3. **スナップショット作成**: デフォルトで**同じ例外が2回発生**した時点でスナップショット作成
4. **アップロード**: スナップショットがApplication Insightsにアップロード（10-15分）

### 制限事項

- **1日最大50スナップショット**
- **10分間に1スナップショット**の制限
- **データ保持期間**: 15日間
- **サポート環境**: .NET Framework 4.6.2以降、.NET 6.0以降（Windows）
- **Consumptionプラン**: 非対応（Basic以上のプラン必要）

### Azure Functions での有効化手順

#### host.json の設定

Function App のルートディレクトリにある `host.json` に追加：

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

#### Azure Government / China Cloud の場合

```json
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "snapshotConfiguration": {
        "isEnabled": true,
        "agentEndpoint": "https://snapshot.monitor.azure.us" // US Government
        // "agentEndpoint": "https://snapshot.monitor.azure.cn"  // China Cloud
      }
    }
  }
}
```

#### アプリケーションの再デプロイ

`host.json` の変更後、Function App を再デプロイ。

### スナップショットの確認方法

#### 方法1: Failures ペインから

```
1. Application Insights → 調査 → 失敗（Failures）
2. 「例外」タブを選択
3. 「[x] サンプル」をクリックして例外リストを表示
4. 例外を選択して詳細ページを開く
5. 「デバッグ スナップショットを開く」ボタンをクリック
```

#### 方法2: Code Optimizations から

```
1. Azure Portal で「Code Optimizations」を検索
2. サブスクリプション・リソースでフィルタ
3. 「Insight type」列で「Exceptions」を探す
4. スナップショットのある例外を選択
```

### スナップショットで確認できる情報

#### ✅ 取得できるデータ

- 例外発生時点の**コールスタック**
- 各フレームの**ローカル変数の値**
- **パラメータの値**
- **例外メッセージとスタックトレース**

#### ❌ 取得できないデータ

- スナップショット以前・以後の実行履歴
- データベースの状態
- 外部APIのレスポンス（変数に保存されていない場合）

### 例外の記録方法

#### 自動収集（ASP.NET/ASP.NET Core）

未処理の例外は自動的に記録されます。

#### 手動記録（処理済み例外）

**Python（Azure Functions）:**

```python
import logging
from applicationinsights import TelemetryClient

tc = TelemetryClient('<instrumentation_key>')

try:
    result = risky_operation()
except Exception as e:
    # 例外をApplication Insightsに送信
    tc.track_exception()
    logging.error(f"Error occurred: {e}", exc_info=True)
    raise
```

**C#（.NET）:**

```csharp
using Microsoft.ApplicationInsights;

try
{
    // 処理
}
catch (Exception ex)
{
    telemetryClient.TrackException(ex);
    throw;
}
```

---

## AMPLS環境でのBYOS設定

### BYOS（Bring Your Own Storage）とは

**Profiler と Snapshot Debugger が収集したデータを自分のストレージアカウントに保存する設定**

### BYOSが必須となる環境

1. **Azure Private Link を使用している場合**（このプロジェクト）
2. **カスタマーマネージドキー（CMK）で暗号化を使用している場合**

### BYOS のメリット

- 診断データへのネットワークアクセスを制御できる
- カスタムの保存時暗号化ポリシーを使用できる
- データ保持ポリシーを管理できる
- コンプライアンスやセキュリティ要件を満たせる

### BYOS 設定手順

#### ステップ1: ストレージアカウントの準備

**前提条件:**

- Application Insights と**同じリージョン**にストレージアカウントを作成
- Private Link使用時は、ストレージアカウントで「信頼されたMicrosoftサービス」を許可

**Terraform での実装例:**

```hcl
# BYOS用のストレージアカウント
resource "azurerm_storage_account" "profiler_byos" {
  name                     = "stprofilerbyos${var.environment}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Private Link環境での設定
  public_network_access_enabled   = false
  default_to_oauth_authentication = true

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]  # 信頼されたMicrosoftサービスを許可
  }
}
```

#### ステップ2: ロール割り当て

**Diagnostic Services Trusted Storage Access アプリケーションに権限付与:**

**Azure CLI:**

```bash
# サービスプリンシパルIDを取得（固定値）
DIAG_SERVICES_APP_ID="f9b2c97d-a755-4e16-9e94-fd0c3d2e9b31"

# ストレージアカウントのリソースIDを取得
STORAGE_ID=$(az storage account show \
  --name <your-storage> \
  --resource-group <your-rg> \
  --query id -o tsv)

# ロール割り当て
az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee $DIAG_SERVICES_APP_ID \
  --scope $STORAGE_ID
```

**Terraform での実装例:**

```hcl
# Diagnostic Services Trusted Storage Access のロール割り当て
resource "azurerm_role_assignment" "profiler_byos" {
  scope                = azurerm_storage_account.profiler_byos.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = "f9b2c97d-a755-4e16-9e94-fd0c3d2e9b31"  # Diagnostic Services Trusted Storage Access
}
```

#### ステップ3: Application Insights とストレージアカウントをリンク

**Azure CLI:**

```bash
az monitor app-insights component linked-storage link \
  --resource-group "<your-rg>" \
  --app "<your-appi>" \
  --storage-account "<your-storage>"
```

**PowerShell:**

```powershell
# ストレージアカウントの取得
$storageAccount = Get-AzStorageAccount `
  -ResourceGroupName "<your-rg>" `
  -Name "<your-storage>"

# リンク作成
New-AzApplicationInsightsLinkedStorageAccount `
  -ResourceGroupName "<your-rg>" `
  -Name "<your-appi>" `
  -LinkedStorageAccountResourceId $storageAccount.Id
```

**Terraform での実装例:**

```hcl
# Application Insights Linked Storage Account
resource "azurerm_application_insights_standard_web_test" "profiler_byos_link" {
  name                               = "profiler-byos-link"
  resource_group_name                = azurerm_resource_group.rg.name
  application_insights_id            = azurerm_application_insights.ai.id
  location                          = azurerm_resource_group.rg.location
  linked_storage_account_resource_id = azurerm_storage_account.profiler_byos.id
}
```

#### ステップ4: Private Endpoint の設定（オプション）

**AMPLS環境で完全にプライベート化する場合:**

```hcl
# ストレージアカウント用のプライベートエンドポイント
resource "azurerm_private_endpoint" "profiler_storage" {
  name                = "pe-profiler-storage"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.private_endpoint.id

  private_service_connection {
    name                           = "psc-profiler-storage"
    private_connection_resource_id = azurerm_storage_account.profiler_byos.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}
```

#### ステップ5: 検証

**リンクが正しく作成されたことを確認:**

```bash
az monitor app-insights component linked-storage show \
  --resource-group "<your-rg>" \
  --app "<your-appi>"
```

**期待される出力:**

```json
{
  "id": "/subscriptions/{sub}/resourceGroups/<your-rg>/providers/Microsoft.Insights/components/<your-appi>/linkedStorageAccounts/serviceprofiler",
  "linkedStorageAccount": "/subscriptions/{sub}/resourceGroups/<your-rg>/providers/Microsoft.Storage/storageAccounts/<your-storage>",
  "name": "serviceprofiler",
  "type": "Microsoft.Insights/components/linkedStorageAccounts"
}
```

---

## 実装手順

### フェーズ1: 基本設定（BYOS不要な環境）

#### 1. Profiler の有効化

```bash
# Function App の環境変数に追加
az functionapp config appsettings set \
  --name <your-func> \
  --resource-group <your-rg> \
  --settings \
    APPINSIGHTS_PROFILERFEATURE_VERSION="1.0.0" \
    DiagnosticServices_EXTENSION_VERSION="~3"
```

#### 2. Snapshot Debugger の有効化

`host.json` に追加:

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

#### 3. Function App の再起動

```bash
az functionapp restart \
  --name <your-func> \
  --resource-group <your-rg>
```

### フェーズ2: BYOS設定（AMPLS環境）

#### 1. リソース作成（Terraform）

```hcl
# main.tf に追加

# BYOS用ストレージアカウント
module "profiler_byos_storage" {
  source = "./modules/core/storage/storageaccount"

  name                = "stprofilerbyos"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  public_network_access_enabled = false
  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

# Diagnostic Services へのロール割り当て
resource "azurerm_role_assignment" "profiler_byos_diag" {
  scope                = module.profiler_byos_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = "f9b2c97d-a755-4e16-9e94-fd0c3d2e9b31"
}

# プライベートエンドポイント
module "pe_profiler_storage" {
  source = "./modules/core/network/private-endpoint/storage"

  name                = "pe-profiler-storage"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  subnet_id           = module.network.private_endpoint_subnet_id

  private_connection_resource_id = module.profiler_byos_storage.id
  subresource_names             = ["blob"]

  dns_zone_ids = [module.dns_blob.id]
}
```

#### 2. リンク作成（デプロイ後の手動操作）

```bash
# Application Insights とストレージをリンク
az monitor app-insights component linked-storage link \
  --resource-group "<your-rg>" \
  --app "<your-appi>" \
  --storage-account "<your-storage>"
```

#### 3. 動作確認

```bash
# Profiler のオンデマンド実行
# Azure Portal: Application Insights → Performance → Profiler → Profile Now

# 5-10分後に結果を確認
# Azure Portal: Application Insights → Performance → Profiler → Recent profiling sessions
```

### フェーズ3: 運用

#### モニタリング

**Profiler の動作確認:**

```kusto
// Application Insights → Logs
traces
| where message has "stopprofiler" or message has "startprofiler"
| project timestamp, message, severityLevel
| order by timestamp desc
```

**Snapshot Debugger の動作確認:**

```kusto
// スナップショットが収集された例外を確認
customEvents
| where name == "ServiceProfilerSample"
| project timestamp, operation_Name, cloud_RoleInstance
| order by timestamp desc
```

#### トリガー調整

**CPU/Memory トリガーの閾値変更:**

```
Application Insights → Performance → Profiler → Triggers
→ CPU または Memory タブ → 閾値を調整
```

---

## トラブルシューティング

### Profiler が動作しない

#### 症状: トレースが表示されない

**確認事項:**

1. **待機時間不足**: Profile Now 後10-15分待つ
2. **リクエストがない**: プロファイリング中にリクエストを送る必要がある
3. **ファイアウォール**: `https://gateway.azureserviceprofiler.net` へのアクセス確認
4. **権限不足**: Application Insights Component Contributor ロール確認

**動作確認クエリ:**

```kusto
traces
| where message has "stopprofiler" or message has "startprofiler" or message has "ServiceProfilerSample"
| project timestamp, message
| order by timestamp desc
```

`ServiceProfilerSample` イベントが表示されていれば正常動作。

#### 症状: BYOS リンクエラー

**エラー: "Storage account location should match AI component location"**

```bash
# ストレージアカウントとApplication Insightsのリージョンを確認
az storage account show --name <your-storage> --query location
az monitor app-insights component show --app <your-appi> --resource-group <your-rg> --query location
```

同じリージョンである必要があります。

### Snapshot Debugger が動作しない

#### 症状: スナップショットが収集されない

**確認事項:**

1. **例外回数**: 同じ例外を2回発生させる
2. **サービスプラン**: Basic以上のプランを使用（Consumption不可）
3. **シンボルファイル**: `.pdb` ファイルがデプロイされているか確認
4. **ロール権限**: `Application Insights Snapshot Debugger` ロールが割り当てられているか

**host.json の確認:**

```bash
# Function App のファイルを確認
az functionapp deployment source show \
  --name <your-func> \
  --resource-group <your-rg>
```

#### 症状: スナップショットは収集されるが表示されない

**権限確認:**

```bash
# 自分のアカウントにSnapshot Debuggerロールを付与
az role assignment create \
  --role "Application Insights Snapshot Debugger" \
  --assignee-object-id $(az ad signed-in-user show --query id -o tsv) \
  --scope $(az monitor app-insights component show \
    --app <your-appi> \
    --resource-group <your-rg> \
    --query id -o tsv)
```

### 一般的な問題

#### ロール割り当ての反映遅延

ロール割り当て後、**5-10分待つ**必要があります。

#### Private Link 環境での接続問題

**ストレージアカウントのネットワーク設定確認:**

```bash
az storage account show \
  --name <your-storage> \
  --query "networkRuleSet.bypass"
```

`AzureServices` が含まれていることを確認。

---

## ベストプラクティス

### 初期段階

1. **Profiler/Snapshot Debugger なしで運用開始**
2. 基本的なメトリクスとログで監視
3. パフォーマンス問題や原因不明の例外が発生したら有効化

### パフォーマンス調査時

1. **Profile Now で即座にプロファイリング**
2. 5-10分後にトレース確認
3. ホットパスを特定
4. コード最適化
5. 再度プロファイリングして改善確認

### 例外調査時

1. **Snapshot Debugger を有効化**
2. 同じ例外を2回発生させる
3. 10-15分後にスナップショット確認
4. 変数値からroot causeを特定
5. 修正後は無効化も検討（コスト削減）

### コスト最適化

- **Profiler データ**: 15日後自動削除（追加コストなし）
- **Snapshot データ**: 15日後自動削除（追加コストなし）
- **BYOS ストレージ**: 自分のストレージアカウントなので、保持ポリシーを設定して古いデータを削除

```hcl
# ストレージアカウントのライフサイクル管理
resource "azurerm_storage_management_policy" "profiler_lifecycle" {
  storage_account_id = azurerm_storage_account.profiler_byos.id

  rule {
    name    = "delete-old-snapshots"
    enabled = true

    filters {
      blob_types = ["blockBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 15
      }
    }
  }
}
```

---

## 参考リンク

- [Application Insights Profiler for .NET](https://learn.microsoft.com/azure/azure-monitor/profiler/profiler-overview)
- [Snapshot Debugger for .NET](https://learn.microsoft.com/azure/azure-monitor/snapshot-debugger/snapshot-debugger)
- [Configure BYOS for Profiler and Snapshot Debugger](https://learn.microsoft.com/azure/azure-monitor/profiler/profiler-bring-your-own-storage)
- [Azure Monitor Private Link Scope](https://learn.microsoft.com/azure/azure-monitor/logs/private-link-security)

---

## 更新履歴

- 2026-03-16: 初版作成
