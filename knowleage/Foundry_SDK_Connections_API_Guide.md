# Azure AI Foundry SDK - Connections API 完全ガイド

## 目次

1. [概要](#概要)
2. [前提条件](#前提条件)
3. [基本的な使い方](#基本的な使い方)
4. [Credential型別アクセス方法](#credential型別アクセス方法)
5. [実用的なコード例](#実用的なコード例)
6. [トラブルシューティング](#トラブルシューティング)
7. [参考資料](#参考資料)

---

## 概要

Azure AI Foundry ProjectのConnectionsには、APIキーや認証情報を安全に保存できます。このガイドでは、Foundry SDK (azure-ai-projects) を使用してConnectionから認証情報を取得する方法を説明します。

### Connectionsで管理できる認証情報

- **APIキー**: 単一のAPI Key
- **カスタムキー**: 複数のキー・バリューペア
- **SASトークン**: Azure Storage用のShared Access Signature
- **Entra ID (旧AAD)**: Managed Identity認証
- **認証なし**: 認証不要のエンドポイント

---

## 前提条件

### 必要なパッケージ

```bash
pip install azure-ai-projects azure-identity
```

### 環境変数

```bash
export PROJECT_ENDPOINT="https://<your-resource>.services.ai.azure.com/api/projects/<project-name>"
```

---

## 基本的な使い方

### 1. AIProjectClientの初期化

```python
import os
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

project_client = AIProjectClient(
    endpoint=os.environ["PROJECT_ENDPOINT"],
    credential=DefaultAzureCredential()
)
```

### 2. Connectionの取得（最重要）

```python
# ⚠️ include_credentials=True が必須！
connection = project_client.connections.get(
    name="conn_funcmcp",
    include_credentials=True  # デフォルトはFalse
)
```

**重要ポイント:**

- `include_credentials`パラメータは**デフォルトでFalse**
- `False`の場合、`connection.credentials`は空になる
- 認証情報を取得するには**必ず`True`を指定**する必要がある

### 3. Connection情報の確認

```python
print(f"Connection Name: {connection.name}")
print(f"Connection Type: {connection.type}")
print(f"Target URL: {connection.target}")
print(f"Credential Type: {connection.credentials.type}")
```

---

## Credential型別アクセス方法

### BaseCredentialsの継承関係

```
BaseCredentials (抽象基底クラス)
├── ApiKeyCredentials (type="ApiKey")
├── CustomCredential (type="CustomKeys")
├── SASCredentials (type="SAS")
├── EntraIDCredentials (type="AAD")
└── NoAuthenticationCredentials (type="None")
```

**重要:** 各サブクラスは**異なる属性名**を持つため、型に応じた分岐処理が必要です。

### 型別の属性一覧

| Credential型                    | type値         | 属性名            | 属性の型         | 説明                     |
| ------------------------------- | -------------- | ----------------- | ---------------- | ------------------------ |
| **ApiKeyCredentials**           | `"ApiKey"`     | `api_key`         | `str \| None`    | 単一のAPIキー            |
| **CustomCredential**            | `"CustomKeys"` | `credential_keys` | `Dict[str, str]` | 複数のカスタムキー(辞書) |
| **SASCredentials**              | `"SAS"`        | `sas_token`       | `str \| None`    | SASトークン              |
| **EntraIDCredentials**          | `"AAD"`        | (なし)            | -                | Managed Identity認証     |
| **NoAuthenticationCredentials** | `"None"`       | (なし)            | -                | 認証不要                 |

### 1. ApiKeyCredentials (単一APIキー)

```python
if connection.credentials.type == "ApiKey":
    # api_key属性にアクセス
    api_key = connection.credentials.api_key
    print(f"API Key: {api_key}")
```

**使用例:**

- OpenAI API Key
- Azure Cognitive Services API Key
- カスタムAPIサービスのキー

### 2. CustomCredential (複数のカスタムキー)

```python
if connection.credentials.type == "CustomKeys":
    # credential_keys辞書にアクセス
    credential_keys = connection.credentials.credential_keys  # Dict[str, str]

    # 全キーの確認
    print(f"Available keys: {list(credential_keys.keys())}")

    # 特定のキーを取得
    if "FUNCMCP_API_KEY" in credential_keys:
        api_key = credential_keys["FUNCMCP_API_KEY"]
        print(f"Function MCP API Key: {api_key}")

    if "SPEECH_API_KEY" in credential_keys:
        speech_key = credential_keys["SPEECH_API_KEY"]
        print(f"Speech API Key: {speech_key}")
```

**使用例:**

- 複数のAPIキーを1つのConnectionで管理
- Function MCP + Speech API + OpenAI APIなど

**Azure Portalでの設定例:**

```json
{
  "properties": {
    "authType": "CustomKeys",
    "category": "CustomKeys",
    "credentials": {
      "keys": {
        "OPENAI_API_KEY": "<your-openai-key>",
        "SPEECH_API_KEY": "<your-speech-key>",
        "FUNCMCP_API_KEY": "<your-funcmcp-key>"
      }
    },
    "target": "_",
    "metadata": {
      "OPENAI_API_BASE": "https://...",
      "OPENAI_API_VERSION": "2024-02-01"
    }
  }
}
```

### 3. SASCredentials (SASトークン)

```python
if connection.credentials.type == "SAS":
    # sas_token属性にアクセス
    sas_token = connection.credentials.sas_token
    print(f"SAS Token: {sas_token}")
```

**使用例:**

- Azure Blob Storage
- Azure Queue Storage
- Azure Table Storage

### 4. EntraIDCredentials (Managed Identity)

```python
if connection.credentials.type == "AAD":
    # Managed Identity認証 - 追加の認証情報は不要
    print("Entra ID (AAD) authentication - no explicit credentials needed")

    # DefaultAzureCredentialを使用して認証
    from azure.identity import DefaultAzureCredential
    credential = DefaultAzureCredential()
```

**使用例:**

- Azure内部リソース間の認証
- Function App → Azure OpenAI
- Function App → Key Vault

### 5. NoAuthenticationCredentials (認証不要)

```python
if connection.credentials.type == "None":
    # 認証不要のエンドポイント
    print("No authentication required")
    print(f"Target URL: {connection.target}")
```

**使用例:**

- パブリックAPI
- 認証不要のWebhook

---

## 実用的なコード例

### 例1: 型に応じた自動判定でAPIキー取得

```python
import os
from typing import Optional
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

def get_connection_api_key(
    project_client: AIProjectClient,
    connection_name: str,
    custom_key_name: Optional[str] = None
) -> str:
    """
    Foundry ConnectionからAPIキーを取得(型に応じて自動判定)

    Args:
        project_client: AIProjectClientインスタンス
        connection_name: Connection名
        custom_key_name: CustomKeys型の場合のキー名(デフォルト: 最初のキー)

    Returns:
        str: API Key

    Raises:
        ValueError: APIキーが取得できない場合
    """
    try:
        # Connectionを取得(credentials付き)
        connection = project_client.connections.get(
            name=connection_name,
            include_credentials=True
        )

        cred_type = connection.credentials.type

        # ApiKey型
        if cred_type == "ApiKey":
            if connection.credentials.api_key:
                return connection.credentials.api_key
            raise ValueError(f"api_key is None for connection '{connection_name}'")

        # CustomKeys型
        elif cred_type == "CustomKeys":
            credential_keys = connection.credentials.credential_keys

            # 指定されたキー名で取得
            if custom_key_name:
                if custom_key_name in credential_keys:
                    return credential_keys[custom_key_name]
                raise ValueError(
                    f"Key '{custom_key_name}' not found in connection '{connection_name}'. "
                    f"Available keys: {list(credential_keys.keys())}"
                )

            # キー名未指定の場合は最初のキーを返す
            if credential_keys:
                first_key = next(iter(credential_keys.values()))
                return first_key
            raise ValueError(f"No keys found in CustomKeys connection '{connection_name}'")

        # SAS型
        elif cred_type == "SAS":
            if connection.credentials.sas_token:
                return connection.credentials.sas_token
            raise ValueError(f"sas_token is None for connection '{connection_name}'")

        # AAD/None型はAPI Key取得不可
        elif cred_type in ["AAD", "None"]:
            raise ValueError(
                f"Connection '{connection_name}' uses {cred_type} authentication. "
                "No API key available."
            )

        else:
            raise ValueError(f"Unsupported credential type: {cred_type}")

    except Exception as e:
        raise ValueError(f"Failed to retrieve API key from connection '{connection_name}': {str(e)}")


# 使用例
if __name__ == "__main__":
    project_client = AIProjectClient(
        endpoint=os.environ["PROJECT_ENDPOINT"],
        credential=DefaultAzureCredential()
    )

    # 例1: ApiKey型のConnection
    api_key = get_connection_api_key(project_client, "conn_openai")
    print(f"OpenAI API Key: {api_key[:10]}...")

    # 例2: CustomKeys型のConnection(キー名指定)
    funcmcp_key = get_connection_api_key(
        project_client,
        "conn_funcmcp",
        custom_key_name="FUNCMCP_API_KEY"
    )
    print(f"Function MCP API Key: {funcmcp_key[:10]}...")

    # 例3: CustomKeys型のConnection(キー名未指定→最初のキー)
    first_key = get_connection_api_key(project_client, "conn_custom")
    print(f"First custom key: {first_key[:10]}...")
```

### 例2: 型安全なパターン(isinstance使用)

```python
from azure.ai.projects.models import (
    BaseCredentials,
    ApiKeyCredentials,
    CustomCredential,
    SASCredentials,
    EntraIDCredentials,
    NoAuthenticationCredentials
)

def get_api_key_safe(connection) -> Optional[str]:
    """型安全にAPIキーを取得"""
    credentials: BaseCredentials = connection.credentials

    # isinstance()で型チェック
    if isinstance(credentials, ApiKeyCredentials):
        return credentials.api_key

    elif isinstance(credentials, CustomCredential):
        # 最初のキーを返す
        if credentials.credential_keys:
            return next(iter(credentials.credential_keys.values()))
        return None

    elif isinstance(credentials, SASCredentials):
        return credentials.sas_token

    elif isinstance(credentials, (EntraIDCredentials, NoAuthenticationCredentials)):
        return None  # API Key不要

    return None
```

### 例3: Function MCPクライアント用のヘルパークラス

```python
import os
import logging
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

class FunctionMCPConnectionManager:
    """Function MCP用のConnection管理クラス"""

    def __init__(self, project_endpoint: str, connection_name: str = "conn_funcmcp"):
        """
        Args:
            project_endpoint: Foundry Project Endpoint
            connection_name: Function MCP Connection名
        """
        self.project_client = AIProjectClient(
            endpoint=project_endpoint,
            credential=DefaultAzureCredential()
        )
        self.connection_name = connection_name
        self._connection = None
        self._api_key = None

    def get_connection(self):
        """Connectionを取得(キャッシュ付き)"""
        if self._connection is None:
            self._connection = self.project_client.connections.get(
                name=self.connection_name,
                include_credentials=True
            )
        return self._connection

    def get_api_key(self) -> str:
        """Function MCP APIキーを取得"""
        if self._api_key is not None:
            return self._api_key

        connection = self.get_connection()
        cred_type = connection.credentials.type

        if cred_type == "ApiKey":
            self._api_key = connection.credentials.api_key

        elif cred_type == "CustomKeys":
            credential_keys = connection.credentials.credential_keys
            # FUNCMCP_API_KEYまたはAPI_KEYを探す
            if "FUNCMCP_API_KEY" in credential_keys:
                self._api_key = credential_keys["FUNCMCP_API_KEY"]
            elif "API_KEY" in credential_keys:
                self._api_key = credential_keys["API_KEY"]
            else:
                available_keys = list(credential_keys.keys())
                raise ValueError(
                    f"Function MCP API key not found. Available keys: {available_keys}"
                )
        else:
            raise ValueError(
                f"Unsupported credential type for Function MCP: {cred_type}"
            )

        if not self._api_key:
            raise ValueError("API key is empty")

        logging.info(f"Function MCP API Key retrieved from connection '{self.connection_name}'")
        return self._api_key

    def get_target_url(self) -> str:
        """Function MCP Target URLを取得"""
        connection = self.get_connection()
        return connection.target


# 使用例
if __name__ == "__main__":
    manager = FunctionMCPConnectionManager(
        project_endpoint=os.environ["PROJECT_ENDPOINT"],
        connection_name="conn_funcmcp"
    )

    # APIキー取得
    api_key = manager.get_api_key()
    print(f"Function MCP API Key: {api_key[:10]}...")

    # Target URL取得
    target_url = manager.get_target_url()
    print(f"Function MCP URL: {target_url}")
```

### 例4: Connectionの一覧取得

```python
def list_all_connections(project_client: AIProjectClient):
    """全Connectionを一覧表示"""
    print("=== All Connections ===")
    for connection in project_client.connections.list():
        print(f"\nName: {connection.name}")
        print(f"  Type: {connection.type}")
        print(f"  Target: {connection.target}")
        print(f"  Is Default: {connection.is_default}")
        # ⚠️ list()ではcredentialsは含まれない


def list_connections_by_type(project_client: AIProjectClient, conn_type: str):
    """特定タイプのConnectionを一覧表示"""
    from azure.ai.projects.models import ConnectionType

    print(f"=== Connections of type: {conn_type} ===")
    for connection in project_client.connections.list(connection_type=conn_type):
        print(f"- {connection.name}: {connection.target}")


# 使用例
if __name__ == "__main__":
    project_client = AIProjectClient(
        endpoint=os.environ["PROJECT_ENDPOINT"],
        credential=DefaultAzureCredential()
    )

    # 全Connection一覧
    list_all_connections(project_client)

    # AzureOpenAI型のみ
    list_connections_by_type(project_client, "AzureOpenAI")
```

---

## トラブルシューティング

### 問題1: credentialsが空になる

**症状:**

```python
connection = project_client.connections.get("conn_funcmcp")
print(connection.credentials)  # None または空
```

**原因:**
`include_credentials`パラメータを指定していない(デフォルトはFalse)

**解決方法:**

```python
connection = project_client.connections.get(
    "conn_funcmcp",
    include_credentials=True  # 必須!
)
```

### 問題2: 属性名が存在しない

**症状:**

```python
AttributeError: 'CustomCredential' object has no attribute 'api_key'
```

**原因:**
Credential型ごとに属性名が異なるのに、ApiKey型の`api_key`属性にアクセスしようとした

**解決方法:**
型をチェックしてから適切な属性にアクセス:

```python
if connection.credentials.type == "ApiKey":
    key = connection.credentials.api_key
elif connection.credentials.type == "CustomKeys":
    key = connection.credentials.credential_keys["FUNCMCP_API_KEY"]
```

### 問題3: KeyError: 'FUNCMCP_API_KEY'

**症状:**

```python
KeyError: 'FUNCMCP_API_KEY'
```

**原因:**
CustomKeys型で存在しないキー名でアクセスしようとした

**解決方法:**

```python
credential_keys = connection.credentials.credential_keys

# 安全な取得方法
if "FUNCMCP_API_KEY" in credential_keys:
    key = credential_keys["FUNCMCP_API_KEY"]
else:
    # getメソッドでデフォルト値付き取得
    key = credential_keys.get("FUNCMCP_API_KEY", "default_value")

    # または利用可能なキーを確認
    available_keys = list(credential_keys.keys())
    print(f"Available keys: {available_keys}")
```

### 問題4: 認証エラー

**症状:**

```python
azure.core.exceptions.ClientAuthenticationError
```

**原因:**

- DefaultAzureCredentialが適切に設定されていない
- RBACロールが不足している

**解決方法:**

```bash
# Azure CLIでログイン
az login

# 必要なRBACロール
# - Azure AI Developer (Foundry Projectへのアクセス)
# - Cognitive Services User (AI Servicesへのアクセス)
```

---

## 参考資料

### 公式ドキュメント

- [ConnectionsOperations.get() API](https://learn.microsoft.com/en-us/python/api/azure-ai-projects/azure.ai.projects.operations.connectionsoperations?view=azure-python#azure-ai-projects-operations-connectionsoperations-get)
- [Connection Model](https://learn.microsoft.com/en-us/python/api/azure-ai-projects/azure.ai.projects.models.connection?view=azure-python)
- [BaseCredentials Model](https://learn.microsoft.com/en-us/python/api/azure-ai-projects/azure.ai.projects.models.basecredentials?view=azure-python)
- [ApiKeyCredentials Model](https://learn.microsoft.com/en-us/python/api/azure-ai-projects/azure.ai.projects.models.apikeycredentials?view=azure-python)
- [CustomCredential Model](https://learn.microsoft.com/en-us/python/api/azure-ai-projects/azure.ai.projects.models.customcredential?view=azure-python)
- [SASCredentials Model](https://learn.microsoft.com/en-us/python/api/azure-ai-projects/azure.ai.projects.models.sascredentials?view=azure-python)
- [EntraIDCredentials Model](https://learn.microsoft.com/en-us/python/api/azure-ai-projects/azure.ai.projects.models.entraidcredentials?view=azure-python)
- [Azure AI Projects SDK Examples](https://learn.microsoft.com/en-us/python/api/overview/azure/ai-projects-readme?view=azure-python#examples)

### SDK情報

```bash
# パッケージ名
azure-ai-projects==1.0.0

# インストール
pip install azure-ai-projects azure-identity

# 依存関係
# - azure-identity (認証)
# - azure-core (Azure SDK共通基盤)
```

### 関連ナレッジ

- [Key Vault認証パターン](../s4_durable_functions/s4_foundry_agents/config/settings.py) - `get_secret_from_keyvault()`関数
- [DefaultAzureCredential](https://learn.microsoft.com/en-us/python/api/azure-identity/azure.identity.defaultazurecredential) - 認証チェーン
- [Managed Identity](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview) - Azure内部リソース間認証

---

## 変更履歴

| 日付       | バージョン | 変更内容                                         |
| ---------- | ---------- | ------------------------------------------------ |
| 2026-01-22 | 1.0.0      | 初版作成 - Foundry SDK Connections API完全ガイド |

---

## まとめ

### 必須チェックリスト

- [ ] `include_credentials=True`を必ず指定する
- [ ] Credential型(type属性)を確認する
- [ ] 型に応じた正しい属性名でアクセスする
  - ApiKey: `api_key`
  - CustomKeys: `credential_keys` (辞書)
  - SAS: `sas_token`
  - AAD/None: 追加属性なし
- [ ] エラーハンドリングを実装する

### よくある間違い

❌ **間違い:**

```python
connection = project_client.connections.get("conn_funcmcp")
key = connection.credentials.api_key  # credentialsが空
```

✅ **正しい:**

```python
connection = project_client.connections.get("conn_funcmcp", include_credentials=True)
if connection.credentials.type == "ApiKey":
    key = connection.credentials.api_key
```

### ベストプラクティス

1. **型チェックを必ず行う**: Credential型に応じた分岐処理を実装
2. **エラーハンドリング**: KeyError、AttributeErrorに対処
3. **ログ出力**: セキュリティのため、APIキーの全文は出力しない
4. **キャッシュ活用**: 同じConnectionを何度も取得しない
5. **環境変数管理**: PROJECT_ENDPOINTは環境変数から取得
