# APIMを介したFoundry IQのナレッジエージェントハンズオン

Azure API Management (APIM) をゲートウェイとして、Foundry IQ の Knowledge Base に接続するナレッジエージェントを構築するハンズオンです。
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

## ACL の仕組み

```
ADLS Gen2 (ais-docs コンテナ)
└── Tartarian/
    └── *.pdf / ← ドキュメント

ADLS ACL:
  - ルート: group (adls-acl-group) = --x  (ディレクトリのトラバースのみ)
  - Tartarian/*: group (adls-acl-group) = r-x  (読み取り可)

AI Search インデクサー:
  - ADLS のグループ ACL を読み取り、GroupIds フィールドとしてインデックスに格納

ユーザー認証 (OBO フロー):
  1. クライアントが Entra ID の oauth-app トークンを取得
  2. MSAL の acquire_token_on_behalf_of() で AI Search 用トークンに交換
  3. x-ms-query-source-authorization ヘッダーにユーザートークンを付与
  4. AI Search が JWT のグループ情報でドキュメントをフィルタリング
```

## ハンズオンナビゲーターエージェント

このハンズオンは AI エージェントと対話しながら進めることもできます。

### Claude Code

Claude Code を使用している場合、チャットで **「ハンズオン始めたい」** と入力するだけでナビゲーターエージェントが起動します。

### GitHub Copilot

GitHub Copilot を使用している場合は、以下の手順で起動します。

1. VS Code のチャットパネルを開く
2. エージェントとして **`handson-navigator-githubcopilot`** を選択（`handson-navigator-claude` は選択しないでください）
3. **「ハンズオン始めたい」** と入力

---

## セットアップ

ハンズオン環境のセットアップ方法は [環境構築](handson/環境構築/環境構築.md) を参照してください。

## ハンズオンシナリオ

`appcodes/` 配下に 3 つのシナリオが用意されています。

→ **[ハンズオンを開始する](handson/ハンズオン/ハンズオン.md)**

## シナリオ比較

| 項目         | `acl_off`                  | `acl_on`                      | `acl_on_classic-rag`            |
| ------------ | -------------------------- | ----------------------------- | ------------------------------- |
| ACL          | なし                       | あり                          | あり                            |
| ゲートウェイ | APIM → Foundry Agent       | APIM → Foundry IQ (MCP)       | APIM → Azure OpenAI / AI Search |
| 認証         | DefaultAzureCredential     | OBO フロー                    | OBO フロー + JWT デコード       |
| RAG          | Foundry Agent が自動       | Foundry IQ が自動             | 自前実装                        |
| API          | `responses.create` (agent) | `responses.create` (MCP tool) | `chat.completions` + Search     |
| 複雑さ       | 低                         | 中                            | 高                              |

---

---

## 技術解説

ハンズオンで体験したアーキテクチャの詳細解説（OBO フロー・セキュリティ・AI 評価・Observability など）はこちら。

→ **[技術解説を読む](handson/tech/tech.md)**

---
