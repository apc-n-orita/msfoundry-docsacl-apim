# 技術解説

ハンズオンで体験したアーキテクチャをより深く理解するための技術解説です。  
以下の順に読み進めることを推奨しますが、関心のあるトピックから読んでも構いません。

---

## 解説一覧

| #   | ドキュメント                                                  | 内容                                                                        |
| --- | ------------------------------------------------------------- | --------------------------------------------------------------------------- |
| 1   | [OBO フロー実運用](./01_obo_flow.md)                          | App Service → Functions → APIM 構成でユーザートークンを安全に伝播させる方法 |
| 2   | [セキュリティ](./02_security.md)                              | APIM ゲートウェイ制御と Foundry ガードレールによる多層防御                  |
| 3   | [AI 評価・Observability](./03_evaluation_observability.md)    | Continuous Evaluation による品質監視とトレース基盤                          |
| 4   | [さらなるセキュリティ強化](./04_advanced_security.md)         | Defender / Entra ID 条件付きアクセス / Purview によるエンタープライズ対応   |
| 5   | [Application Insights Profiler](./05_appinsights_profiler.md) | トレースだけでは解決できない障害調査のための高度なデバッグ機能              |

---

## 各ドキュメントの概要

### 1. OBO フロー実運用

Foundry IQ の ACL 機能をブラウザアプリから利用するために必要な、**EasyAuth → トークンストア → OBO フロー**の一連の流れを解説します。

- App Service の EasyAuth によるユーザー認証とトークンストア管理
- Functions が 401 を返したときの自動リフレッシュの仕組み
- Functions 内での MSAL OBO フロー実装

→ [OBO フロー実運用を読む](./01_obo_flow.md)

---

### 2. セキュリティ

APIM ポリシー (`validate-azure-ad-token`・`llm-token-limit`・バックエンドプール) の実装内容と、Foundry ガードレールによる入出力フィルタリングを解説します。

- Entra ID トークン検証とグループベースのアクセス制御
- TPM レート制限・クォータ制御
- セッションアフィニティとサーキットブレーカー
- Foundry ガードレール vs Azure Language Service PII 検出の使い分け

→ [セキュリティを読む](./02_security.md)

---

### 3. AI 評価・Observability

実運用の AI エージェントの品質を継続的に評価・監視する方法を解説します。

- Continuous Evaluation の設定と評価メトリクス（Groundedness / Task Adherence など）
- ハンズオンで構築した分散トレース基盤の活用
- Grafana Dashboard 追加予定

→ [AI 評価・Observability を読む](./03_evaluation_observability.md)

---

### 4. さらなるセキュリティ強化

エンタープライズ環境で求められる高度なセキュリティ対策を解説します。

- Microsoft Defender for Cloud による AI 脅威保護とエージェントインベントリ管理
- Entra ID 条件付きアクセス for Agent ID（IP 制限ではなく Identity Protection ポリシー）
- Microsoft Purview による AI インタラクションのデータガバナンス

→ [さらなるセキュリティ強化を読む](./04_advanced_security.md)

---

### 5. Application Insights Profiler / Snapshot Debugger

トレース・ログだけでは原因が特定できない障害に対する、高度なデバッグ機能を解説します。

- Profiler によるメソッド単位のパフォーマンス分析
- Snapshot Debugger による本番固有の例外調査
- Private Link 環境（AMPLS）での BYOS 設定

→ [Application Insights Profiler を読む](./05_appinsights_profiler.md)

---

## 次のステップ

- [OBO フロー実運用](./01_obo_flow.md)

---

## 前の手順

ハンズオンがまだの場合は先に [ハンズオン](../ハンズオン/ハンズオン.md) を完了させてください。

---

<!--
  ここまで読んでくれたあなたへ
-->

[ここまで読んでくれたあなたへ](../extra/spirituality_in_it.md)
