# Azure Language Service PII Detection API 実装ガイド

## 概要

本ドキュメントは、Azure AI Foundryのエージェント開発において個人情報（PII: Personally Identifiable Information）を検出・マスキングするための実装ガイドです。

## PII検出の2つのアプローチ

### 1. Azure OpenAI Content Filtering (シンプルなアプローチ)

**特徴:**

- Azure AI Foundry / Azure OpenAI APIに組み込み済み
- 設定は簡単（APIリクエストパラメータで指定）
- **制限事項: PIIが検出されると出力全体をブロック（部分的なマスキング不可）**

**使用ケース:**

- 単純なPII検出が必要な場合
- PII含有テキストを完全に拒否したい場合

**設定方法:**

```python
# Azure OpenAI APIでのPIIフィルター有効化例
response = client.chat.completions.create(
    model="gpt-4",
    messages=[{"role": "user", "content": "..."}],
    content_filter={
        "pii": {
            "mode": "Annotate and Block",  # PIIを検出してブロック
            "severity": "高"
        }
    }
)
```

### 2. Azure Language Service PII Detection API (高度なアプローチ)

**特徴:**

- **部分的なマスキングが可能**（テキスト全体をブロックせず、PII部分のみ置換）
- 4種類のマスキングポリシーから選択可能
- 信頼度スコア閾値の設定が可能
- 特定のPII種別のみフィルタリング可能

**使用ケース:**

- テキストを保持しつつPII部分のみをマスキングしたい場合
- 監査ログや証憑データの匿名化
- プライバシーコンプライアンスが必要な場合

---

## Azure Language Service PII Detection API 詳細

### 前提条件

1. **Azure Language Serviceリソースの作成**
   - Azure Portalで「Language Service」リソースを作成
   - エンドポイントURLとAPIキーを取得

2. **環境変数の設定**

**Linux/Mac:**

```bash
export LANGUAGE_ENDPOINT="https://your-resource-name.cognitiveservices.azure.com/"
export LANGUAGE_KEY="your-api-key-here"
```

**Windows (PowerShell):**

```powershell
$env:LANGUAGE_ENDPOINT="https://your-resource-name.cognitiveservices.azure.com/"
$env:LANGUAGE_KEY="your-api-key-here"
```

3. **Python SDKのインストール**

```bash
pip install azure-ai-textanalytics==5.3.0
```

---

## Microsoft Foundry (new) での GUI利用

### 概要

Azure Language ServiceのPII Detection機能は、**Microsoft Foundry (new)** ポータルでGUIベースで直接利用できます。コーディング不要でテストや検証が可能です。

**✅ 部分的なマスキングが可能**: テキスト全体をブロックせず、PII部分のみをマスキングできます。

### アクセス方法

#### 方法A: Discoverタブから

1. Microsoft Foundry (new) ポータル (https://ai.azure.com/) にアクセス
2. 上部ナビゲーションバーの **Discover** タブを選択
3. Models検索バーに「**Azure**」と入力してEnter
4. 検索結果から「**Azure-Language-Text-PII redaction**」を選択
5. **Open in Playground** ボタンをクリック

#### 方法B: Buildタブから

1. 上部ナビゲーションバーの **Build** タブを選択
2. 左ナビゲーションバーの **Models** を選択
3. **AI services** タブを選択
4. **Azure-Language-Text-PII redaction** を選択してPlaygroundへ

### 設定方法

#### 1. テキスト入力

- サンプルテキストを選択
- 📎アイコンでファイルをアップロード
- 手動でテキストを入力

#### 2. Configure設定

**Configure** ボタンをクリックして以下のオプションを設定:

| オプション                   | 説明                         | 推奨設定                                         |
| ---------------------------- | ---------------------------- | ------------------------------------------------ |
| **API version**              | 使用するAPIバージョン        | `latest` または `2024-11-15-preview`             |
| **Model version**            | 使用するモデルバージョン     | `latest`                                         |
| **Language**                 | テキストの言語               | `ja` (日本語)                                    |
| **Types**                    | 検出したいPII種別            | `Person`, `Email`, `PhoneNumber`, `Address` など |
| **Specify redaction policy** | マスキング方法（下記参照）   | `CharacterMask` (デフォルト)                     |
| **Excluded values**          | マスキングから除外する値     | 必要に応じて指定                                 |
| **Synonyms**                 | 関連する同義語を対象にするか | 必要に応じてON                                   |

#### 3. マスキングポリシーの選択

**Specify redaction policy** で以下の4つから選択:

##### ① CharacterMask（文字マスク）- デフォルト

- **動作**: PII部分のみを指定文字（`*`）で置換
- **例**: `田中太郎のSSNは859-98-0987です。` → `****のSSNは************です。`
- **用途**: 文脈を保ちつつPII部分のみマスキング ✅ **推奨**

##### ② EntityMask（エンティティタイプマスク）

- **動作**: PII部分をエンティティタイプ名で置換
- **例**: `田中太郎のSSNは859-98-0987です。` → `[PERSON_1]のSSNは[US_SOCIAL_SECURITY_NUMBER_1]です。`
- **用途**: PIIの種類を明示しつつマスキング

##### ③ SyntheticReplacement（合成データ置換）

- **動作**: PII部分を同じカテゴリの合成データで置換
- **例**: `田中太郎のSSNは859-98-0987です。` → `山田花子のSSNは123-45-6789です。`
- **用途**: テスト環境用データ生成

##### ④ NoMask（マスクなし）

- **動作**: テキストはそのまま、エンティティ情報のみ返却
- **用途**: PII位置の確認のみ

#### 4. 実行と結果確認

1. 設定完了後、**Detect** ボタンをクリック
2. 検出されたPIIがハイライト表示される
3. 結果はフォーマット済みテキストまたはJSONレスポンスで確認可能

**結果に含まれる情報:**

| フィールド     | 説明                                               |
| -------------- | -------------------------------------------------- |
| **Type**       | 検出されたPII種別 (Person, Email, PhoneNumberなど) |
| **Confidence** | 信頼度スコア (0.0～1.0)                            |
| **Offset**     | テキスト開始位置からの文字数                       |
| **Length**     | エンティティの文字数                               |

### GUI利用の制限事項

- **Foundry (new)** では「**Extract PII from text**」のみサポート
- **会話形式PII**（Extract PII from conversation）は「**Foundry (classic)**」で利用
- GUI切り替え: ポータル上部のバージョントグルで切り替え可能

### ユースケース

| シナリオ             | 推奨方法                     |
| -------------------- | ---------------------------- |
| **開発前の動作確認** | GUI (Foundry new Playground) |
| **テストデータ作成** | GUI + SyntheticReplacement   |
| **本番実装**         | Python SDK / REST API (後述) |
| **エージェント統合** | Python SDK (後述)            |

---

## 実装方法

### Python SDKを使用した実装

#### 基本的な実装例

```python
import os
from azure.ai.textanalytics import TextAnalyticsClient
from azure.core.credentials import AzureKeyCredential

# 環境変数から認証情報を取得
endpoint = os.environ["LANGUAGE_ENDPOINT"]
key = os.environ["LANGUAGE_KEY"]

# クライアントの初期化
client = TextAnalyticsClient(
    endpoint=endpoint,
    credential=AzureKeyCredential(key)
)

# PII検出の実行
documents = [
    "田中太郎のSSNは859-98-0987です。連絡先は tanaka@example.com です。"
]

response = client.recognize_pii_entities(documents, language="ja")

# 結果の処理
for doc in response:
    if not doc.is_error:
        print(f"元のテキスト: {documents[0]}")
        print(f"マスク後のテキスト: {doc.redacted_text}")
        print("\n検出されたPIIエンティティ:")
        for entity in doc.entities:
            print(f"  - テキスト: {entity.text}")
            print(f"    カテゴリ: {entity.category}")
            print(f"    信頼度スコア: {entity.confidence_score}")
            print(f"    位置: {entity.offset} (長さ: {entity.length})")
    else:
        print(f"エラー: {doc.error.message}")
```

**出力例:**

```
元のテキスト: 田中太郎のSSNは859-98-0987です。連絡先は tanaka@example.com です。
マスク後のテキスト: ****のSSNは************です。連絡先は ********************* です。

検出されたPIIエンティティ:
  - テキスト: 田中太郎
    カテゴリ: Person
    信頼度スコア: 0.95
    位置: 0 (長さ: 4)
  - テキスト: 859-98-0987
    カテゴリ: USSocialSecurityNumber
    信頼度スコア: 0.88
    位置: 10 (長さ: 12)
  - テキスト: tanaka@example.com
    カテゴリ: Email
    信頼度スコア: 0.92
    位置: 30 (長さ: 19)
```

#### 追加設定オプション付き実装

```python
from azure.ai.textanalytics import TextAnalyticsClient, PiiEntityCategory
from azure.core.credentials import AzureKeyCredential
import os

# クライアント初期化
endpoint = os.environ["LANGUAGE_ENDPOINT"]
key = os.environ["LANGUAGE_KEY"]
client = TextAnalyticsClient(endpoint=endpoint, credential=AzureKeyCredential(key))

documents = ["田中太郎のSSNは859-98-0987です。電話番号は03-1234-5678です。"]

# 追加設定オプションを指定
response = client.recognize_pii_entities(
    documents,
    language="ja",

    # オプション1: 特定のPII種別のみを検出
    categories_filter=[
        PiiEntityCategory.PERSON,
        PiiEntityCategory.US_SOCIAL_SECURITY_NUMBER,
        PiiEntityCategory.PHONE_NUMBER,
        PiiEntityCategory.EMAIL
    ],

    # オプション2: ドメイン指定 (医療情報のみ検出したい場合)
    domain_filter="phi",  # Protected Healthcare Information
    # domain_filter=None,  # すべてのドメイン (デフォルト)

    # オプション3: モデルバージョン指定
    model_version="latest",

    # オプション4: 文字オフセット方式の指定
    string_index_type="UnicodeCodePoint",  # Python標準 (デフォルト)

    # オプション5: サービスログ無効化（プライバシー保護）
    disable_service_logs=True,  # サービス側でログを記録しない

    # オプション6: 統計情報を含める
    show_stats=True
)

# 結果の処理
for doc in response:
    if not doc.is_error:
        print(f"元のテキスト: {documents[0]}")
        print(f"マスク後: {doc.redacted_text}")

        if hasattr(doc, 'statistics') and doc.statistics:
            print(f"\n統計情報:")
            print(f"  - 文字数: {doc.statistics.character_count}")
            print(f"  - トランザクション数: {doc.statistics.transaction_count}")

        print(f"\n検出されたPIIエンティティ:")
        for entity in doc.entities:
            print(f"  - エンティティ: {entity.text}")
            print(f"    カテゴリ: {entity.category}")
            print(f"    信頼度スコア: {entity.confidence_score}")
```

---

### REST APIを使用した実装

#### 基本的なREST APIリクエスト

```bash
curl -X POST "https://your-resource-name.cognitiveservices.azure.com/language/:analyze-text?api-version=2024-11-15-preview" \
-H "Content-Type: application/json" \
-H "Ocp-Apim-Subscription-Key: YOUR_API_KEY" \
-d '{
  "kind": "PiiEntityRecognition",
  "parameters": {
    "modelVersion": "latest"
  },
  "analysisInput": {
    "documents": [
      {
        "id": "1",
        "language": "ja",
        "text": "田中太郎のSSNは859-98-0987です。"
      }
    ]
  }
}'
```

#### Pythonでのリクエスト実装

```python
import os
import requests

endpoint = os.environ["LANGUAGE_ENDPOINT"]
key = os.environ["LANGUAGE_KEY"]

url = f"{endpoint}/language/:analyze-text?api-version=2024-11-15-preview"

headers = {
    "Content-Type": "application/json",
    "Ocp-Apim-Subscription-Key": key
}

payload = {
    "kind": "PiiEntityRecognition",
    "parameters": {
        "modelVersion": "latest"
    },
    "analysisInput": {
        "documents": [
            {
                "id": "1",
                "language": "ja",
                "text": "田中太郎のSSNは859-98-0987です。"
            }
        ]
    }
}

response = requests.post(url, json=payload, headers=headers)
result = response.json()

print("検出結果:")
for doc in result.get("results", {}).get("documents", []):
    print(f"マスク後テキスト: {doc['redactedText']}")
    for entity in doc.get("entities", []):
        print(f"  - {entity['text']} ({entity['category']}): 信頼度 {entity['confidenceScore']}")
```

---

## マスキングポリシーの設定

### 4種類のマスキングポリシー

#### 1. characterMask (文字マスク) - デフォルト

**動作:** PII部分を指定文字（デフォルト: `*`）で置換

**例:**

- 元のテキスト: `田中太郎のSSNは859-98-0987です。`
- マスク後: `****のSSNは************です。`

**REST API設定:**

```json
{
  "kind": "PiiEntityRecognition",
  "parameters": {
    "redactionPolicies": [
      {
        "policyKind": "characterMask",
        "redactionCharacter": "*"
      }
    ]
  },
  "analysisInput": { ... }
}
```

#### 2. entityMask (エンティティタイプマスク)

**動作:** PII部分をエンティティタイプ名（例: `[PERSON_1]`）で置換

**例:**

- 元のテキスト: `田中太郎のSSNは859-98-0987です。`
- マスク後: `[PERSON_1]のSSNは[US_SOCIAL_SECURITY_NUMBER_1]です。`

**REST API設定:**

```json
{
  "kind": "PiiEntityRecognition",
  "parameters": {
    "redactionPolicies": [
      {
        "policyKind": "entityMask"
      }
    ]
  },
  "analysisInput": { ... }
}
```

#### 3. syntheticReplacement (合成データ置換)

**動作:** PII部分を同じカテゴリの合成データで置換

**例:**

- 元のテキスト: `田中太郎のSSNは859-98-0987です。`
- マスク後: `山田花子のSSNは123-45-6789です。`

**REST API設定:**

```json
{
  "kind": "PiiEntityRecognition",
  "parameters": {
    "redactionPolicies": [
      {
        "policyKind": "syntheticReplacement"
      }
    ]
  },
  "analysisInput": { ... }
}
```

#### 4. noMask (マスクなし)

**動作:** テキストはそのまま、エンティティ情報のみ返却

**例:**

- 元のテキスト: `田中太郎のSSNは859-98-0987です。`
- マスク後: `田中太郎のSSNは859-98-0987です。` (変更なし、検出情報のみ取得)

**REST API設定:**

```json
{
  "kind": "PiiEntityRecognition",
  "parameters": {
    "redactionPolicies": [
      {
        "policyKind": "noMask"
      }
    ]
  },
  "analysisInput": { ... }
}
```

---

## 追加設定オプション

> **⚠️ Python SDK (`azure-ai-textanalytics`) の `recognize_pii_entities` メソッドについて**
>
> `recognize_pii_entities` で直接指定できるフィルタリングパラメータは **`categories_filter`** と **`domain_filter`** のみです（下記 2, 3）。
> それ以外の高度なカスタマイズ（1, 4〜8）は、Python SDK にまだパラメータとして実装されていないため、Python の `requests` ライブラリで REST API を直接呼び出す必要があります。

### 1. 信頼度スコア閾値の設定 (API version 2025-11-15-preview)

**用途:** 低信頼度のPII誤検出を除外

```json
{
  "kind": "PiiEntityRecognition",
  "parameters": {
    "confidenceScoreThreshold": {
      "default": 0.9,
      "overrides": [
        {
          "value": 0.8,
          "entity": "USSocialSecurityNumber"
        },
        {
          "value": 0.6,
          "entity": "Person",
          "language": "ja"
        }
      ]
    }
  },
  "analysisInput": { ... }
}
```

**説明:**

- `default`: すべてのエンティティのデフォルト閾値
- `overrides`: 特定エンティティ・言語ごとの個別設定

### 2. 特定のPII種別のみフィルタリング ✅ `recognize_pii_entities` 対応

**Python SDK（`recognize_pii_entities` で直接指定可能）:**

```python
from azure.ai.textanalytics import PiiEntityCategory

response = client.recognize_pii_entities(
    documents,
    categories_filter=[
        PiiEntityCategory.PERSON,
        PiiEntityCategory.EMAIL,
        PiiEntityCategory.PHONE_NUMBER
    ]
)
```

**REST API:**

```json
{
  "kind": "PiiEntityRecognition",
  "parameters": {
    "piiCategories": [
      "Person",
      "Email",
      "PhoneNumber"
    ]
  },
  "analysisInput": { ... }
}
```

### 3. ドメイン指定フィルター ✅ `recognize_pii_entities` 対応

**Python SDK（`recognize_pii_entities` で直接指定可能）— 医療情報 (PHI) のみ検出:**

```python
response = client.recognize_pii_entities(
    documents,
    domain_filter="phi"  # Protected Healthcare Information
)
```

### 4. 特定の値をマスキングから除外 (`valueExclusionPolicy`) ⚠️ REST API のみ

**用途:** PIIカテゴリに該当しても、特定の値をマスキング対象から除外する。例: 警察が「police officer」「suspect」等の人物関連語をマスキングしたくない場合。

> `recognize_pii_entities` では未対応。Python の `requests` ライブラリで REST API を直接呼ぶ必要がある。

**Python（REST API 直接呼び出し）:**

```python
import os
import requests

endpoint = os.environ["LANGUAGE_ENDPOINT"]
key = os.environ["LANGUAGE_KEY"]

url = f"{endpoint}/language/:analyze-text?api-version=2024-11-15-preview"

headers = {
    "Content-Type": "application/json",
    "Ocp-Apim-Subscription-Key": key
}

payload = {
    "kind": "PiiEntityRecognition",
    "parameters": {
        "modelVersion": "latest",
        "redactionPolicy": {
            "policyKind": "characterMask",
            "redactionCharacter": "*"
        },
        "valueExclusionPolicy": {
            "caseSensitive": False,
            "excludedValues": [
                "APC株式会社",
                "サポート窓口"
            ]
        }
    },
    "analysisInput": {
        "documents": [
            {
                "id": "1",
                "language": "ja",
                "text": "APC株式会社の田中太郎がサポート窓口に連絡しました。"
            }
        ]
    }
}

response = requests.post(url, json=payload, headers=headers)
result = response.json()

# 結果: "APC株式会社の****がサポート窓口に連絡しました。"
# → 除外指定した「APC株式会社」「サポート窓口」はマスキングされない
```

**ポイント:**

- `caseSensitive`: 大文字小文字を区別するか（デフォルト: false）
- `excludedValues`: 除外したい値のリスト（完全一致、部分文字列は除外されない）

### 5. カスタム同義語の定義 (`entitySynonyms`) ⚠️ REST API のみ

**用途:** モデルが認識できない専門用語・略語・業界固有の表現を、既存のPIIカテゴリに紐づけて検出精度を向上させる。

> `recognize_pii_entities` では未対応。Python の `requests` ライブラリで REST API を直接呼ぶ必要がある。

**Python（REST API 直接呼び出し）:**

```python
import os
import requests

endpoint = os.environ["LANGUAGE_ENDPOINT"]
key = os.environ["LANGUAGE_KEY"]

url = f"{endpoint}/language/:analyze-text?api-version=2024-11-15-preview"

headers = {
    "Content-Type": "application/json",
    "Ocp-Apim-Subscription-Key": key
}

payload = {
    "kind": "PiiEntityRecognition",
    "parameters": {
        "modelVersion": "latest",
        "entitySynonyms": [
            {
                "entityType": "InternationalBankingAccountNumber",
                "synonyms": [
                    {"synonym": "BAN", "language": "en"},
                    {"synonym": "国際口座番号", "language": "ja"}
                ]
            },
            {
                "entityType": "Person",
                "synonyms": [
                    {"synonym": "担当者名", "language": "ja"},
                    {"synonym": "申請者", "language": "ja"}
                ]
            }
        ]
    },
    "analysisInput": {
        "documents": [
            {
                "id": "1",
                "language": "ja",
                "text": "担当者名: 田中太郎、国際口座番号: GB29NWBK60161331926819"
            }
        ]
    }
}

response = requests.post(url, json=payload, headers=headers)
result = response.json()
```

**対応エンティティ一覧:**

| エンティティ         | entityType                          | 同義語の例                   |
| -------------------- | ----------------------------------- | ---------------------------- |
| ABAルーティング番号  | `ABARoutingNumber`                  | Routing transit number (RTN) |
| 住所                 | `Address`                           | My place is                  |
| 年齢                 | `Age`                               | Years old, 年齢              |
| 銀行口座番号         | `BankAccountNumber`                 | Bank acct no., 口座番号      |
| クレジットカード番号 | `CreditCardNumber`                  | Cc number, カード番号        |
| 日付                 | `DateTime`                          | Given date, 指定日           |
| 生年月日             | `DateOfBirth`                       | Birthday, DOB, 誕生日        |
| IBAN                 | `InternationalBankingAccountNumber` | IBAN, 国際口座番号           |
| 組織                 | `Organization`                      | company, 会社, 法人          |
| 人名                 | `Person`                            | Name, 担当者名, 申請者       |
| 人物種別             | `PersonType`                        | Role, 役職                   |
| 電話番号             | `PhoneNumber`                       | Landline, 携帯番号           |
| SWIFTコード          | `SWIFTCode`                         | BIC, 銀行識別コード          |

**注意事項:**

- まず同義語なしでテストし、精度が不十分な場合のみ同義語を追加すること
- 同義語は意味的に正確な語句に限定する（例: 「BAN」→ OK、「deposit」→ NG）
- 同一の同義語を複数のエンティティに使い回すことはできない

### 6. エンティティ検証の無効化 (`disableEntityValidation`) ⚠️ REST API のみ — API version 2025-11-15-preview

**用途:** デフォルトのエンティティバリデーション（データ整合性チェック・偽陽性削減）を無効化し、検出を高速化する。バリデーション不要なワークフローで有効。

> `recognize_pii_entities` では未対応。Python の `requests` ライブラリで REST API を直接呼ぶ必要がある。

**Python（REST API 直接呼び出し）:**

```python
import os
import requests

endpoint = os.environ["LANGUAGE_ENDPOINT"]
key = os.environ["LANGUAGE_KEY"]

url = f"{endpoint}/language/:analyze-text?api-version=2025-11-15-preview"

headers = {
    "Content-Type": "application/json",
    "Ocp-Apim-Subscription-Key": key
}

payload = {
    "kind": "PiiEntityRecognition",
    "parameters": {
        "modelVersion": "latest",
        "disableEntityValidation": True
    },
    "analysisInput": {
        "documents": [
            {
                "id": "1",
                "language": "ja",
                "text": "田中太郎のSSNは859-98-0987です。"
            }
        ]
    }
}

response = requests.post(url, json=payload, headers=headers)
result = response.json()
```

**注意:** バリデーション無効化により偽陽性が増える可能性があるため、精度よりもパフォーマンスを優先したい場合のみ使用すること。

### 7. エンティティ別マスキングポリシーの指定 (`redactionPolicies`) ⚠️ REST API のみ — API version 2025-11-15-preview

**用途:** エンティティ種別ごとに異なるマスキング方法を適用する。例えば人名は合成データ置換、電話番号は文字マスクと使い分けが可能。

> `recognize_pii_entities` では未対応。Python の `requests` ライブラリで REST API を直接呼ぶ必要がある。

**Python（REST API 直接呼び出し）:**

```python
import os
import requests

endpoint = os.environ["LANGUAGE_ENDPOINT"]
key = os.environ["LANGUAGE_KEY"]

url = f"{endpoint}/language/:analyze-text?api-version=2025-11-15-preview"

headers = {
    "Content-Type": "application/json",
    "Ocp-Apim-Subscription-Key": key
}

payload = {
    "kind": "PiiEntityRecognition",
    "parameters": {
        "modelVersion": "latest",
        "redactionPolicies": [
            {
                "policyKind": "syntheticReplacement",
                "entityTypes": ["Person"]
            },
            {
                "policyKind": "characterMask",
                "redactionCharacter": "*",
                "entityTypes": ["PhoneNumber", "Email"]
            },
            {
                "policyKind": "entityMask",
                "entityTypes": ["Address"]
            }
        ]
    },
    "analysisInput": {
        "documents": [
            {
                "id": "1",
                "language": "ja",
                "text": "田中太郎の電話番号は03-1234-5678、住所は東京都千代田区1-1です。"
            }
        ]
    }
}

response = requests.post(url, json=payload, headers=headers)
result = response.json()

# 結果例:
# "山田花子の電話番号は************、住所は[ADDRESS_1]です。"
# → Person: 合成データ置換、PhoneNumber: 文字マスク、Address: エンティティマスク
```

### 8. カスタム正規表現によるPII検出（コンテナ版のみ）

**用途:** PII Detection コンテナを利用する場合、独自の正規表現ルールでカスタムエンティティを検出できる。社内固有のID体系など、標準のエンティティに含まれないパターンの検出に有効。

**コンテナ起動時の設定:**

```bash
docker run --rm -it -p 5000:5000 --memory 8g --cpus 1 \
  mcr.microsoft.com/azure-cognitive-services/textanalytics/pii:{IMAGE_TAG} \
  Eula=accept \
  Billing={ENDPOINT_URI} \
  ApiKey={API_KEY} \
  UserRegexRuleFilePath=/rules/custom_rules.json
```

**正規表現ルールファイルの例 (`custom_rules.json`):**

```json
[
  {
    "name": "CE_CompanyEmployeeId",
    "description": "社内従業員IDの検出ルール（APC-で始まる8桁の英数字）",
    "regexPatterns": [
      {
        "id": "EmployeeIdPattern",
        "pattern": "(?<!\\w)(APC-[A-Z0-9]{8})(?!\\w)",
        "matchScore": 0.85,
        "locales": ["ja", "en"]
      }
    ],
    "matchContext": {
      "hints": [
        {
          "hintText": "従業員(\\s*)ID|社員(\\s*)番号|employee(\\s*)id",
          "boostingScore": 0.1,
          "locales": ["ja", "en"]
        }
      ]
    }
  }
]
```

**制約事項:**

- ルール名は `CE_` で始まる必要がある
- ルール名は一意でなければならない
- 正規表現は .NET 形式に準拠
- **クラウドAPI（REST API / Python SDK）では利用不可、コンテナ版のみ**

---

### フィルタリング・カスタマイズ機能まとめ

| カスタマイズ機能                      | 概要                     | `recognize_pii_entities` 対応 | 利用方法              | API版              |
| ------------------------------------- | ------------------------ | ----------------------------- | --------------------- | ------------------ |
| `categories_filter` / `piiCategories` | 特定のPII種別のみ検出    | ✅ 対応                       | SDK直接指定           | GA                 |
| `domain_filter`                       | ドメイン指定（PHI等）    | ✅ 対応                       | SDK直接指定           | GA                 |
| `valueExclusionPolicy`                | 特定の値を除外           | ❌ 未対応                     | `requests` + REST API | GA                 |
| `entitySynonyms`                      | カスタム同義語           | ❌ 未対応                     | `requests` + REST API | GA                 |
| `confidenceScoreThreshold`            | 信頼度閾値               | ❌ 未対応                     | `requests` + REST API | 2025-11-15-preview |
| `redactionPolicies` (エンティティ別)  | 種別ごとのマスキング方法 | ❌ 未対応                     | `requests` + REST API | 2025-11-15-preview |
| `disableEntityValidation`             | バリデーション無効化     | ❌ 未対応                     | `requests` + REST API | 2025-11-15-preview |
| カスタム正規表現                      | 独自パターン定義         | ❌ 未対応                     | コンテナのみ          | コンテナ版         |

**公式ドキュメント:** [Adapt PII to your domain](https://learn.microsoft.com/azure/ai-services/language-service/personally-identifiable-information/how-to/adapt-to-domain-pii)

---

## PII種別カテゴリ全一覧

Azure Language Service PII Detection API が検出・マスキング可能なエンティティは、以下の **7つの大分類** に整理されています。

公式ドキュメント: https://aka.ms/azsdk/language/pii

### 1. Geolocation（位置情報）

個人の物理的な所在地を特定・追跡できるデータ。特定の個人に紐づく場合にPIIとみなされます。

| piiCategories パラメータ | 説明                 | 状態    |
| ------------------------ | -------------------- | ------- |
| `Airport`                | 空港                 | preview |
| `City`                   | 市区町村             | preview |
| `GPE`                    | 地政学的エンティティ | preview |
| `Location`               | 場所                 | preview |
| `State`                  | 州/都道府県          | preview |

### 2. Personal（個人情報）

個人を直接的に識別・連絡できるデータ（氏名、SSN等）、または他のデータと組み合わせて識別につながるデータ（住所、生年月日等）。

| piiCategories パラメータ | 説明                   | 状態    |
| ------------------------ | ---------------------- | ------- |
| `Address`                | 住所                   | GA      |
| `Age`                    | 年齢                   | GA      |
| `DateOfBirth`            | 生年月日               | preview |
| `DriversLicenseNumber`   | 運転免許証番号（汎用） | preview |
| `Email`                  | メールアドレス         | GA      |
| `IPAddress`              | IPアドレス             | GA      |
| `LicensePlate`           | ナンバープレート       | preview |
| `PassportNumber`         | パスポート番号（汎用） | preview |
| `Password`               | パスワード             | preview |
| `Person`                 | 人名                   | GA      |
| `PhoneNumber`            | 電話番号               | GA      |
| `URL`                    | URL                    | GA      |
| `VIN`                    | 車両識別番号           | preview |

### 3. Financial（金融情報）

特定の個人に紐づく金融関連の識別情報。

| piiCategories パラメータ            | 説明                        | 状態    |
| ----------------------------------- | --------------------------- | ------- |
| `ABARoutingNumber`                  | ABAルーティング番号（米国） | GA      |
| `BankAccountNumber`                 | 銀行口座番号（汎用）        | preview |
| `CreditCardNumber`                  | クレジットカード番号        | GA      |
| `CVV`                               | カード認証値                | preview |
| `InternationalBankingAccountNumber` | IBAN（国際銀行口座番号）    | GA      |
| `SortCode`                          | ソートコード（英国）        | preview |
| `SWIFTCode`                         | SWIFTコード                 | GA      |

### 4. Organization（組織）

| piiCategories パラメータ | 説明   | 状態 |
| ------------------------ | ------ | ---- |
| `Organization`           | 組織名 | GA   |

### 5. DateTime（日時）

単独ではPIIとみなされない場合もあるが、他のデータと組み合わさると機密性が高くなるデータ。

| piiCategories パラメータ | 説明     | 状態    |
| ------------------------ | -------- | ------- |
| `Date`                   | 日付     | GA      |
| `ExpirationDate`         | 有効期限 | preview |

### 6. Azure-related（Azure関連の秘密情報）

Azure の認証情報や接続文字列など、個人や系統を識別・追跡可能な情報。

| piiCategories パラメータ                  | 説明                   |
| ----------------------------------------- | ---------------------- |
| `AzureDocumentDBAuthKey`                  | Cosmos DB 認証キー     |
| `AzureIAASDatabaseConnectionAndSQLString` | IaaS DB接続文字列      |
| `AzureIoTConnectionString`                | IoT Hub 接続文字列     |
| `AzurePublishSettingPassword`             | 発行設定パスワード     |
| `AzureRedisCacheString`                   | Redis Cache 接続文字列 |
| `AzureSAS`                                | SASトークン            |
| `AzureServiceBusString`                   | Service Bus 接続文字列 |
| `AzureStorageAccountGeneric`              | Storage アカウント情報 |
| `AzureStorageAccountKey`                  | Storage アカウントキー |
| `SQLServerConnectionString`               | SQL Server 接続文字列  |

### 7. Government（政府発行ID）

政府が発行する個人・法人の識別番号。国ごとに固有のエンティティが定義されています。

#### 7-1. 日本固有エンティティ（8種）

| piiCategories パラメータ       | 種別     | 説明                     | 例                 |
| ------------------------------ | -------- | ------------------------ | ------------------ |
| `JPBankAccountNumber`          | 金融     | 銀行口座番号             | 口座番号・支店番号 |
| `JPDriversLicenseNumber`       | 個人ID   | 運転免許証番号           | 12桁の免許証番号   |
| `JPMyNumberCorporate`          | 法人ID   | マイナンバー（法人番号） | 13桁の法人番号     |
| `JPMyNumberPersonal`           | 個人ID   | マイナンバー（個人番号） | 12桁の個人番号     |
| `JPPassportNumber`             | 個人ID   | パスポート番号           | 旅券番号           |
| `JPResidenceCardNumber`        | 個人ID   | 在留カード番号           | 外国人の在留カード |
| `JPResidentRegistrationNumber` | 個人ID   | 住民票コード             | 11桁の住民票コード |
| `JPSocialInsuranceNumber`      | 社会保障 | 社会保険番号             | 基礎年金番号等     |

#### 7-2. その他主要国エンティティ（抜粋）

**米国:**

| piiCategories パラメータ             | 説明                          |
| ------------------------------------ | ----------------------------- |
| `USBankAccountNumber`                | 銀行口座番号                  |
| `USDriversLicenseNumber`             | 運転免許証番号                |
| `USIndividualTaxpayerIdentification` | 個人納税者番号（ITIN）        |
| `USSocialSecurityNumber`             | 社会保障番号（SSN）           |
| `USUKPassportNumber`                 | 米英パスポート番号            |
| `USMedicareBeneficiaryId`            | メディケア受給者ID（preview） |

**英国:**

| piiCategories パラメータ    | 説明           |
| --------------------------- | -------------- |
| `UKDriversLicenseNumber`    | 運転免許証番号 |
| `UKElectoralRollNumber`     | 選挙人名簿番号 |
| `UKNationalHealthNumber`    | NHS番号        |
| `UKNationalInsuranceNumber` | 国民保険番号   |
| `UKUniqueTaxpayerNumber`    | 固有納税者番号 |

**EU共通:**

| piiCategories パラメータ         | 説明               |
| -------------------------------- | ------------------ |
| `EUDebitCardNumber`              | デビットカード番号 |
| `EUDriversLicenseNumber`         | 運転免許証番号     |
| `EUGPSCoordinates`               | GPS座標            |
| `EUNationalIdentificationNumber` | 国民ID番号         |
| `EUPassportNumber`               | パスポート番号     |
| `EUSocialSecurityNumber`         | 社会保障番号       |
| `EUTaxIdentificationNumber`      | 税ID番号           |

**韓国:**

| piiCategories パラメータ       | 説明           | 状態    |
| ------------------------------ | -------------- | ------- |
| `KRDriversLicenseNumber`       | 運転免許証番号 | preview |
| `KRPassportNumber`             | パスポート番号 | preview |
| `KRResidentRegistrationNumber` | 住民登録番号   | GA      |
| `KRSocialSecurityNumber`       | 社会保障番号   | preview |

**その他対応国:** オーストラリア(AU)、オーストリア(AT)、ベルギー(BE)、ブラジル(BR)、ブルガリア(BG)、カナダ(CA)、チリ(CL)、中国(CN)、クロアチア(HR)、キプロス(CY)、チェコ(CZ)、デンマーク(DK)、エストニア(EE)、フィンランド(FI)、フランス(FR)、ドイツ(DE)、ギリシャ(GR)、香港(HK)、ハンガリー(HU)、インド(IN)、インドネシア(ID)、アイルランド(IE)、イスラエル(IL)、イタリア(IT)、ラトビア(LV)、リトアニア(LT)、ルクセンブルク(LU)、マレーシア(MY)、マルタ(MT)、オランダ(NL)、ニュージーランド(NZ)、ノルウェー(NO)、フィリピン(PH)、ポーランド(PL)、ポルトガル(PT)、ルーマニア(RO)、ロシア(RU)、サウジアラビア(SA)、シンガポール(SG)、スロバキア(SK)、スロベニア(SI)、南アフリカ(ZA)、スペイン(ES)、スウェーデン(SE)、スイス(CH)、台湾(TW)、タイ(TH)、トルコ(TR)、ウクライナ(UA)

各国につき国民ID・パスポート番号・運転免許番号・税番号・銀行口座番号等のエンティティが定義されています。全エンティティの完全なリストは[公式ドキュメント](https://learn.microsoft.com/en-us/azure/ai-services/language-service/personally-identifiable-information/concepts/entity-categories-list)を参照してください。

### エンティティ数サマリー

| 大分類        | エンティティ数      |
| ------------- | ------------------- |
| Geolocation   | 5                   |
| Personal      | 13                  |
| Financial     | 7                   |
| Organization  | 1                   |
| DateTime      | 2                   |
| Azure-related | 10                  |
| Government    | 約100以上（50か国） |
| **合計**      | **約140以上**       |

---

## セキュリティベストプラクティス

### 1. Azure Key Vaultを使用した認証情報管理

**推奨される実装:**

```python
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.ai.textanalytics import TextAnalyticsClient
from azure.core.credentials import AzureKeyCredential

# Key Vaultからシークレット取得
credential = DefaultAzureCredential()
vault_url = "https://your-keyvault-name.vault.azure.net/"
secret_client = SecretClient(vault_url=vault_url, credential=credential)

language_key = secret_client.get_secret("LANGUAGE-API-KEY").value
language_endpoint = secret_client.get_secret("LANGUAGE-ENDPOINT").value

# Language Serviceクライアント初期化
client = TextAnalyticsClient(
    endpoint=language_endpoint,
    credential=AzureKeyCredential(language_key)
)
```

### 2. Managed Identityを使用した実運用認証

**Azure Functions / App Serviceでの実装:**

```python
from azure.identity import ManagedIdentityCredential
from azure.ai.textanalytics import TextAnalyticsClient

# Managed Identityで認証
credential = ManagedIdentityCredential()
endpoint = "https://your-resource-name.cognitiveservices.azure.com/"

client = TextAnalyticsClient(
    endpoint=endpoint,
    credential=credential
)
```

**必要な設定:**

1. Azure PortalでManaged Identityを有効化
2. Language Serviceリソースに「Cognitive Services User」ロールを付与

### 3. プライバシー設定

```python
response = client.recognize_pii_entities(
    documents,
    disable_service_logs=True  # サービス側でログを記録しない
)
```

---

## Azure Durable Functions への統合例

### ユースケース

- 音声データアップロード → 文字起こし → PII検出・マスキング
- 画像・書類アップロード → OCR → PII検出・マスキング

### 実装例 (Azure Durable Functions統合)

```python
import azure.durable_functions as df
from azure.ai.textanalytics import TextAnalyticsClient
from azure.core.credentials import AzureKeyCredential
import os

def orchestrator_function(context: df.DurableOrchestrationContext):
    """PII検出統合オーケストレーター"""

    # Step 1: 音声文字起こし
    transcription = yield context.call_activity("transcribe_audio", audio_data)

    # PII検出・マスキング
    masked_transcription = yield context.call_activity("mask_pii", transcription)

    # Step 2: OCR処理
    ocr_text = yield context.call_activity("ocr_document", document_image)

    # PII検出・マスキング
    masked_ocr_text = yield context.call_activity("mask_pii", ocr_text)

    # 分析処理
    analysis_result = yield context.call_activity("analyze_content", {
        "transcription": masked_transcription,
        "ocr_text": masked_ocr_text
    })

    return analysis_result

def mask_pii_activity(text: str) -> str:
    """PII検出・マスキングアクティビティ"""
    endpoint = os.environ["LANGUAGE_ENDPOINT"]
    key = os.environ["LANGUAGE_KEY"]

    client = TextAnalyticsClient(
        endpoint=endpoint,
        credential=AzureKeyCredential(key)
    )

    response = client.recognize_pii_entities(
        [text],
        language="ja",
        categories_filter=[
            "Person",
            "PhoneNumber",
            "Email",
            "Address"
        ],
        disable_service_logs=True
    )

    for doc in response:
        if not doc.is_error:
            return doc.redacted_text

    return text  # エラー時は元のテキストを返す
```

---

## トラブルシューティング

### エラー1: 認証エラー (401 Unauthorized)

**原因:** APIキーまたはエンドポイントが正しくない

**解決策:**

```python
# 環境変数の確認
import os
print(f"Endpoint: {os.environ.get('LANGUAGE_ENDPOINT')}")
print(f"Key exists: {bool(os.environ.get('LANGUAGE_KEY'))}")
```

### エラー2: レート制限エラー (429 Too Many Requests)

**原因:** API呼び出し頻度が制限を超過

**解決策:**

```python
import time
from azure.core.exceptions import HttpResponseError

def call_with_retry(client, documents, max_retries=3):
    for attempt in range(max_retries):
        try:
            return client.recognize_pii_entities(documents)
        except HttpResponseError as e:
            if e.status_code == 429 and attempt < max_retries - 1:
                wait_time = 2 ** attempt  # エクスポネンシャルバックオフ
                time.sleep(wait_time)
            else:
                raise
```

### エラー3: バッチサイズ超過

**制限:** 1リクエストあたり最大10ドキュメント

**解決策:**

```python
def batch_process(client, documents, batch_size=10):
    results = []
    for i in range(0, len(documents), batch_size):
        batch = documents[i:i + batch_size]
        response = client.recognize_pii_entities(batch)
        results.extend(response)
    return results
```

---

## Foundry Agent からの利用方法

### 概要

Azure AI Foundry のエージェント（Agent Framework）から PII Detection 機能を利用する方法は主に以下の3つです:

1. **Function Calling（Tools）として統合** - エージェントがツールとして呼び出し ✅ 推奨
2. **エージェント内で直接実装** - Python コード内で直接 API 呼び出し
3. **Promptflow 統合** - Promptflow のカスタムツールとして実装

---

### 方法1: Function Calling（Tools）として統合 ✅ 推奨

エージェントがLLMに「PII検出が必要」と判断した際に自動的に呼び出すツールとして実装します。

#### 実装例 (Azure AI Foundry SDK)

```python
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import FunctionTool
from azure.ai.textanalytics import TextAnalyticsClient
from azure.core.credentials import AzureKeyCredential
from azure.identity import DefaultAzureCredential
import os
import json

# PII検出ツールの実装
def detect_and_mask_pii(text: str, language: str = "ja", masking_policy: str = "characterMask") -> str:
    """
    テキストからPIIを検出してマスキング

    Args:
        text: 検出対象のテキスト
        language: テキストの言語コード（デフォルト: ja）
        masking_policy: マスキング方法 (characterMask, entityMask, syntheticReplacement, noMask)

    Returns:
        マスキング済みテキスト
    """
    endpoint = os.environ["LANGUAGE_ENDPOINT"]
    key = os.environ["LANGUAGE_KEY"]

    client = TextAnalyticsClient(
        endpoint=endpoint,
        credential=AzureKeyCredential(key)
    )

    response = client.recognize_pii_entities(
        [text],
        language=language,
        categories_filter=["Person", "Email", "PhoneNumber", "Address"],
        disable_service_logs=True
    )

    for doc in response:
        if not doc.is_error:
            return doc.redacted_text

    return text

# Function Tool定義
pii_detection_tool = FunctionTool(
    name="detect_and_mask_pii",
    description="テキストから個人情報（PII）を検出してマスキングします。人名、メールアドレス、電話番号、住所などを自動的に置換します。",
    parameters={
        "type": "object",
        "properties": {
            "text": {
                "type": "string",
                "description": "PII検出を行う対象テキスト"
            },
            "language": {
                "type": "string",
                "description": "テキストの言語コード（ja, en など）",
                "default": "ja"
            },
            "masking_policy": {
                "type": "string",
                "enum": ["characterMask", "entityMask", "syntheticReplacement", "noMask"],
                "description": "マスキング方法の選択",
                "default": "characterMask"
            }
        },
        "required": ["text"]
    }
)

# Foundry Project Client初期化
project_client = AIProjectClient.from_connection_string(
    credential=DefaultAzureCredential(),
    conn_str=os.environ["AIPROJECT_CONNECTION_STRING"]
)

# Agentの作成
agent = project_client.agents.create_agent(
    model="gpt-4o",
    name="PII-Aware Agent",
    instructions="""
    あなたはテキスト処理を支援するエージェントです。
    ユーザーから提供されたテキストに個人情報が含まれている可能性がある場合は、
    detect_and_mask_pii ツールを使用して自動的にマスキングしてください。
    マスキング後のテキストを使って分析を行います。
    """,
    tools=[pii_detection_tool],
    tool_resources={}
)

# エージェント実行
thread = project_client.agents.create_thread()

message = project_client.agents.create_message(
    thread_id=thread.id,
    role="user",
    content="以下のテキストを確認してください。担当者: 田中太郎、連絡先: tanaka@example.com"
)

run = project_client.agents.create_and_process_run(
    thread_id=thread.id,
    assistant_id=agent.id
)

# 結果取得
messages = project_client.agents.list_messages(thread_id=thread.id)
for msg in messages:
    print(f"{msg.role}: {msg.content[0].text.value}")
```

#### Function Calling実行フロー

```
User: "以下のテキストを確認してください。担当者: 田中太郎、連絡先: tanaka@example.com"
  ↓
Agent (LLM): PIIを検出 → detect_and_mask_pii() ツールを呼び出し
  ↓
Tool実行: detect_and_mask_pii("担当者: 田中太郎、連絡先: tanaka@example.com")
  ↓
Tool結果: "担当者: ****、連絡先: *********************"
  ↓
Agent (LLM): マスキング済みテキストで分析を実行
  ↓
Response: "テキストを確認しました。個人情報は適切にマスキングされています..."
```

---

### 方法2: エージェント内で直接実装

エージェントのコード内で明示的にPII検出APIを呼び出します。

#### 実装例

```python
from azure.ai.projects import AIProjectClient
from azure.ai.textanalytics import TextAnalyticsClient
from azure.core.credentials import AzureKeyCredential
from azure.identity import DefaultAzureCredential
import os

class PIIAwareAgent:
    def __init__(self):
        # Language Service Client
        self.pii_client = TextAnalyticsClient(
            endpoint=os.environ["LANGUAGE_ENDPOINT"],
            credential=AzureKeyCredential(os.environ["LANGUAGE_KEY"])
        )

        # Foundry Project Client
        self.project_client = AIProjectClient.from_connection_string(
            credential=DefaultAzureCredential(),
            conn_str=os.environ["AIPROJECT_CONNECTION_STRING"]
        )

        # Agent作成
        self.agent = self.project_client.agents.create_agent(
            model="gpt-4o",
            name="Direct PII Agent",
            instructions="テキスト処理とPII検出を支援します。"
        )

    def mask_pii(self, text: str) -> str:
        """PII検出・マスキング"""
        response = self.pii_client.recognize_pii_entities(
            [text],
            language="ja",
            categories_filter=["Person", "Email", "PhoneNumber"],
            disable_service_logs=True
        )

        for doc in response:
            if not doc.is_error:
                return doc.redacted_text
        return text

    def process_text(self, input_text: str) -> dict:
        """テキスト処理（PII検出・マスキング付き）"""
        # Step 1: PII検出・マスキング
        masked_text = self.mask_pii(input_text)

        # Step 2: マスキング済みテキストでエージェント実行
        thread = self.project_client.agents.create_thread()

        message = self.project_client.agents.create_message(
            thread_id=thread.id,
            role="user",
            content=f"以下のテキストを分析してください:\n{masked_text}"
        )

        run = self.project_client.agents.create_and_process_run(
            thread_id=thread.id,
            assistant_id=self.agent.id
        )

        # Step 3: 結果取得
        messages = self.project_client.agents.list_messages(thread_id=thread.id)

        return {
            "original_text": input_text,
            "masked_text": masked_text,
            "result": messages[0].content[0].text.value
        }

# 使用例
agent = PIIAwareAgent()
result = agent.process_text(
    "担当者: 田中太郎\nメール: tanaka@example.com\n内容: サンプルテキスト"
)

print(f"マスキング後: {result['masked_text']}")
print(f"処理結果: {result['result']}")
```

---

### 方法3: Promptflow 統合

Promptflow のカスタムツールとして PII Detection を実装します。

#### promptflow_tools/pii_detection.py

```python
from promptflow import tool
from azure.ai.textanalytics import TextAnalyticsClient
from azure.core.credentials import AzureKeyCredential
import os

@tool
def detect_pii(
    text: str,
    language: str = "ja",
    masking_policy: str = "characterMask"
) -> dict:
    """
    PII検出・マスキングツール

    Args:
        text: 検出対象テキスト
        language: 言語コード
        masking_policy: マスキング方法

    Returns:
        {
            "masked_text": マスキング済みテキスト,
            "entities": 検出されたPIIエンティティリスト,
            "entity_count": 検出数
        }
    """
    endpoint = os.environ["LANGUAGE_ENDPOINT"]
    key = os.environ["LANGUAGE_KEY"]

    client = TextAnalyticsClient(
        endpoint=endpoint,
        credential=AzureKeyCredential(key)
    )

    response = client.recognize_pii_entities(
        [text],
        language=language,
        disable_service_logs=True
    )

    for doc in response:
        if not doc.is_error:
            entities = [
                {
                    "text": entity.text,
                    "category": entity.category,
                    "confidence": entity.confidence_score
                }
                for entity in doc.entities
            ]

            return {
                "masked_text": doc.redacted_text,
                "entities": entities,
                "entity_count": len(entities)
            }

    return {
        "masked_text": text,
        "entities": [],
        "entity_count": 0
    }
```

#### flow.dag.yaml

```yaml
inputs:
  claim_text:
    type: string
    default: "申請者: 田中太郎、メール: tanaka@example.com"

outputs:
  audit_result:
    type: string
    reference: ${audit_agent.output}

nodes:
  - name: pii_detection
    type: python
    source:
      type: code
      path: promptflow_tools/pii_detection.py
    inputs:
      text: ${inputs.claim_text}
      language: "ja"
      masking_policy: "characterMask"

  - name: audit_agent
    type: llm
    source:
      type: code
      path: audit_prompts.jinja2
    inputs:
      deployment_name: gpt-4o
      masked_text: ${pii_detection.output.masked_text}
      entity_count: ${pii_detection.output.entity_count}
```

---

### 利用シーン別の推奨方法

| シーン                    | 推奨方法         | 理由                                 |
| ------------------------- | ---------------- | ------------------------------------ |
| **自律的にPII検出が必要** | Function Calling | LLMが自動判断して実行                |
| **常にPII検出を実行**     | 直接実装         | 確実に実行される                     |
| **複雑なフロー**          | Promptflow       | 可視化・デバッグが容易               |
| **マルチエージェント**    | Function Calling | 各エージェントが共通ツールとして利用 |
| **シンプルな統合**        | 直接実装         | コード量が少ない                     |

---

### セキュリティ考慮事項

#### 1. Managed Identity の使用

```python
from azure.identity import DefaultAzureCredential

# Managed Identity で Language Service に接続
credential = DefaultAzureCredential()
client = TextAnalyticsClient(
    endpoint=os.environ["LANGUAGE_ENDPOINT"],
    credential=credential  # API Key の代わりに Managed Identity
)
```

#### 2. Foundry Connection の活用

```python
# Foundry Project で Connection を作成して利用
connection = project_client.connections.get(connection_name="language-service-connection")
endpoint = connection.properties["endpoint"]
```

#### 3. ログ無効化

```python
# PII を含むデータはサービス側でログを記録しない
response = client.recognize_pii_entities(
    documents,
    disable_service_logs=True  # 必須
)
```

---

## 参考資料

### 公式ドキュメント

- [Azure Language Service PII Detection 概要](https://learn.microsoft.com/en-us/azure/ai-services/language-service/personally-identifiable-information/overview)
- [Python SDK リファレンス](https://learn.microsoft.com/en-us/python/api/azure-ai-textanalytics/azure.ai.textanalytics)
- [REST API リファレンス](https://learn.microsoft.com/en-us/rest/api/language/)
- [サポートされているPII種別一覧](https://aka.ms/azsdk/language/pii)

### Azure AI Foundry関連

- [Azure AI Content Safety](https://learn.microsoft.com/en-us/azure/ai-services/content-safety/)
- [Azure OpenAI Content Filtering](https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/content-filter)

---

## まとめ

### GUI vs プログラマティック利用の対比

| 項目                      | Microsoft Foundry (new) GUI | Python SDK / REST API           |
| ------------------------- | --------------------------- | ------------------------------- |
| **コーディング**          | 不要 ✅                     | 必要 ⚠️                         |
| **用途**                  | テスト・検証・デモ          | 本番実装・自動化                |
| **部分マスキング**        | 可能 ✅                     | 可能 ✅                         |
| **マスキングポリシー**    | 4種類すべて対応             | 4種類すべて対応                 |
| **信頼度スコア閾値**      | GUIでは不可                 | API (2025-11-15-preview) で可能 |
| **バッチ処理**            | 手動                        | 自動化可能                      |
| **Durable Functions統合** | 不可                        | 可能 ✅                         |
| **エージェント統合**      | 不可                        | 可能 ✅                         |
| **セキュリティ**          | Portalアクセス制御          | Managed Identity対応            |
| **会話形式PII**           | Foundry (classic)で可能     | SDK/APIで可能                   |

### 実装の選択指針

| 要件                                      | 推奨アプローチ                                       |
| ----------------------------------------- | ---------------------------------------------------- |
| 動作確認・テストのみ                      | Microsoft Foundry (new) GUI ✅                       |
| PIIを含むテキストを完全にブロックしたい   | Azure OpenAI Content Filtering                       |
| テキストを保持しつつPII部分のみマスキング | Azure Language Service PII API                       |
| 医療情報のみ検出                          | Azure Language Service (domain_filter="phi")         |
| 特定のPII種別のみ検出                     | Azure Language Service (categories_filter)           |
| 信頼度スコア閾値の制御                    | Azure Language Service REST API (2025-11-15-preview) |
| 開発の容易さ優先                          | Python SDK                                           |
| 詳細な制御が必要                          | REST API直接利用                                     |
| エージェント統合（自律的）                | Function Calling（Tools）✅                          |
| エージェント統合（確実実行）              | エージェント内で直接実装                             |
| 複雑なフロー（可視化重視）                | Promptflow統合                                       |

### 実装チェックリスト

#### Phase 1: 基本セットアップ

- [ ] Azure Language Serviceリソースの作成
- [ ] 環境変数の設定（LANGUAGE_ENDPOINT, LANGUAGE_KEY）
- [ ] Python SDKのインストール (`azure-ai-textanalytics`)

#### Phase 2: GUI検証 ✅ 推奨

- [ ] **Microsoft Foundry (new) GUIでの動作確認**
  - [ ] Playgroundでテストデータを入力して動作確認
  - [ ] 各マスキングポリシーの動作確認
  - [ ] 検出精度と信頼度スコアの確認
  - [ ] 日本語テキストでの精度確認

#### Phase 3: SDK実装

- [ ] 基本的なPII検出の動作確認（コード実装）
- [ ] マスキングポリシーの選択・テスト
- [ ] エラーハンドリングの実装
  - [ ] レート制限対応（Exponential Backoff）
  - [ ] バッチ処理実装

#### Phase 4: Foundry Agent統合 ⭐ 重要

- [ ] **Function Calling（Tools）として実装**
  - [ ] PII検出ツールの定義
  - [ ] エージェントへのツール登録
  - [ ] 自動呼び出しテスト
- [ ] **または、エージェント内で直接実装**
  - [ ] エージェントクラスにPII検出メソッド追加
  - [ ] 明示的な呼び出しテスト

#### Phase 5: アプリケーション統合

- [ ] Durable Functions統合
  - [ ] 音声文字起こし後のPII検出
  - [ ] OCR抽出後のPII検出
- [ ] またはFoundry Agent統合
  - [ ] エージェントワークフローへの組み込み

#### Phase 6: セキュリティ強化

- [ ] セキュリティベストプラクティスの適用
  - [ ] Key Vault統合
  - [ ] Managed Identity対応
  - [ ] サービスログ無効化（disable_service_logs=True）

#### Phase 7: ドキュメント

- [ ] 非機能要件ドキュメントへの反映

### 推奨実装フロー

#### パターンA: Foundry Agent統合（推奨）

```
Step 1: GUI検証 (Microsoft Foundry new)
  ↓ サンプルデータでマスキングポリシーを確認
  ↓ 検出精度を評価

Step 2: SDK実装 (Python)
  ↓ 基本的な実装でテスト
  ↓ エラーハンドリング追加

Step 3: Foundry Agent統合
  ↓ Function Calling（Tools）として実装
  ↓ エージェントに登録して動作確認
  ↓ OR 直接実装パターンを選択

Step 4: セキュリティ強化
  ↓ Managed Identity対応
  ↓ Key Vault統合
```

#### パターンB: Durable Functions統合

```
Step 1: GUI検証 (Microsoft Foundry new)
  ↓ サンプルデータでマスキングポリシーを確認
  ↓ 検出精度を評価

Step 2: SDK実装 (Python)
  ↓ 基本的な実装でテスト
  ↓ エラーハンドリング追加

Step 3: Durable Functions統合
  ↓ Activity関数として実装
  ↓ Orchestratorから呼び出し

Step 4: セキュリティ強化
  ↓ Managed Identity対応
  ↓ Key Vault統合
```

---

**関連ドキュメント:**

- [PII エンティティカテゴリ一覧（公式）](https://aka.ms/azsdk/language/pii)
- [Azure Language Service PII Detection 概要](https://learn.microsoft.com/en-us/azure/ai-services/language-service/personally-identifiable-information/overview)
