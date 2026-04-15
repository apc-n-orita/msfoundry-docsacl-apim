# EasyAuthトークンをAzure AI Search用トークンに交換する設定ガイド

## 概要

EasyAuth（Azure App Service認証）で取得したユーザートークンを、Azure AI Searchの`x-ms-query-source-authorization`ヘッダーで使用するために、**On-Behalf-Of (OBO) フロー**を使用してトークンを交換します。

## 前提条件

- Azure App ServiceでEasyAuthが有効
- Azure Entra ID（旧Azure AD）アプリ登録済み
- Azure AI Searchサービス

## 1. Azure Entra ID アプリケーション設定

### 1.1 API権限の追加

Azure Portal > Azure Entra ID > アプリの登録 > あなたのアプリ > API のアクセス許可

1. **「アクセス許可の追加」** をクリック
2. **「所属する組織で使用している API」** タブを選択
3. **「Azure AI Search」** または **「Azure Search Service」** を検索
   - 見つからない場合は、Application ID: `797f4846-ba00-4fd7-ba43-dac1f8f63013` で検索
4. **「委任されたアクセス許可」** を選択
5. **`user_impersonation`** にチェック
6. **「アクセス許可の追加」** をクリック
7. **「管理者の同意を与える」** をクリック（テナント管理者権限が必要）

### 1.2 公開されたスコープの設定（オプション）

OBOフローを使用するアプリケーション自身も公開APIとして設定する必要がある場合があります。

Azure Portal > Azure Entra ID > アプリの登録 > あなたのアプリ > API の公開

1. **「アプリケーション ID URI」** を設定（例: `api://<your-client-id>`）
2. **「スコープの追加」** で `user_impersonation` スコープを追加

### 1.3 クライアントシークレットの作成

Azure Portal > Azure Entra ID > アプリの登録 > あなたのアプリ > 証明書とシークレット

1. **「新しいクライアント シークレット」** をクリック
2. 説明と有効期限を入力
3. **「追加」** をクリック
4. **値をコピーして安全に保存**（後で取得できません）

## 2. 必要な情報の収集

以下の情報を環境変数または設定ファイルに保存:

```bash
# Azure Entra ID設定
AZURE_TENANT_ID="your-tenant-id"
AZURE_CLIENT_ID="your-client-id"
AZURE_CLIENT_SECRET="your-client-secret"

# Azure AI Search設定
SEARCH_SERVICE_NAME="testaif"
SEARCH_SERVICE_ENDPOINT="https://testaif.search.windows.net"
SEARCH_INDEX_NAME="index-acl-groups"
```

---

## 【追加】Managed Identity フェデレーション（Workload Identity Federation）によるトークン交換（Python）

### 概要

従来の「サービスプリンシパルのシークレット」や「証明書」ではなく、**マネージドIDのフェデレーション（Workload Identity Federation）** を使ってMSALでトークン交換が可能です。これにより、シークレットレスで安全な認証が実現できます。

### 公式ドキュメント

- [Workload identity federation (MSAL.NET)](https://learn.microsoft.com/entra/msal/dotnet/acquiring-tokens/web-apps-apis/workload-identity-federation)
- [MSAL Python Managed Identity](https://learn.microsoft.com/entra/msal/python/advanced/managed-identity#examples)

### Pythonサンプル（Workload Identity FederationでOBOトークン交換）

```python
import msal
import os
import requests

# 1. Managed Identityのアサーションを作成
from msal.managed_identity import SystemAssignedManagedIdentity, ManagedIdentityClient, UserAssignedManagedIdentity

managed_identity = SystemAssignedManagedIdentity()
# ユーザー割り当てIDの場合
#managed_identity = UserAssignedManagedIdentity(client_id=...)
mi_client = ManagedIdentityClient(managed_identity, http_client=requests.Session())

# 2. ManagedIdentityClientAssertionを使う
from msal import ManagedIdentityClientAssertion
mi_assertion = ManagedIdentityClientAssertion(mi_client)

# 3. ConfidentialClientApplicationでclient_credentialにアサーションを指定
authority = f"https://login.microsoftonline.com/{os.getenv('AZURE_TENANT_ID')}"
app = msal.ConfidentialClientApplication(
    client_id=os.getenv('AZURE_CLIENT_ID'),
    client_credential=mi_assertion,  # ここがWorkload Identity Federationのポイント
    authority=authority
)

# 4. OBOフローでトークン交換
result = app.acquire_token_on_behalf_of(
    user_assertion=easyauth_token,  # EasyAuthで取得したアクセストークン
    scopes=["https://search.azure.com/.default"]
)

if "access_token" in result:
    print("トークン取得成功", result["access_token"])
else:
    print("トークン取得失敗", result)
```

#### ポイント

- `client_credential`に`ManagedIdentityClientAssertion`を指定することで、シークレットレスでOBOトークン交換が可能
- Entra IDアプリ登録でWorkload Identity Federation（Federated Credential）を有効化しておくこと
- サービスプリンシパルのシークレットや証明書は不要
- User-assigned Managed Identityの場合は`UserAssignedManagedIdentity`を使う

---

## 3. Pythonパッケージのインストール

```bash
pip install msal requests azure-functions
```

## 4. 実装パターン

### パターン1: Azure Functions（推奨）

```python
import azure.functions as func
import msal
import requests
import os
import json

def exchange_token_for_search(easyauth_token: str) -> str:
    """EasyAuthトークンをSearch用トークンに交換"""
    authority = f"https://login.microsoftonline.com/{os.getenv('AZURE_TENANT_ID')}"
    app = msal.ConfidentialClientApplication(
        client_id=os.getenv('AZURE_CLIENT_ID'),
        client_credential=os.getenv('AZURE_CLIENT_SECRET'),
        authority=authority
    )

    result = app.acquire_token_on_behalf_of(
        user_assertion=easyauth_token,
        scopes=["https://search.azure.com/.default"]
    )

    if "access_token" in result:
        return result["access_token"]
    else:
        raise Exception(f"トークン交換失敗: {result.get('error_description')}")

def main(req: func.HttpRequest) -> func.HttpResponse:
    # EasyAuthトークンを取得
    easyauth_token = req.headers.get("X-MS-TOKEN-AAD-ACCESS-TOKEN")
    if not easyauth_token:
        return func.HttpResponse("認証が必要です", status_code=401)

    # Search用トークンに交換
    search_user_token = exchange_token_for_search(easyauth_token)

    # サービストークン（Managed Identityまたはサービスプリンシパル）
    from azure.identity import DefaultAzureCredential
    credential = DefaultAzureCredential()
    service_token = credential.get_token("https://search.azure.com/.default").token

    # Azure AI Searchクエリ
    search_url = f"{os.getenv('SEARCH_SERVICE_ENDPOINT')}/indexes/{os.getenv('SEARCH_INDEX_NAME')}/docs/search"
    headers = {
        "Authorization": f"Bearer {service_token}",
        "x-ms-query-source-authorization": f"Bearer {search_user_token}",
        "Content-Type": "application/json"
    }

    query_text = req.params.get("query", "")
    body = {
        "search": query_text,
        "count": True,
        "vectorQueries": [{
            "kind": "text",
            "text": query_text,
            "fields": "snippet_vector"
        }],
        "queryType": "semantic",
        "semanticConfiguration": "semantic-configuration",
        "captions": "extractive",
        "answers": "extractive|count-3",
        "queryLanguage": "ja-jp"
    }

    response = requests.post(
        search_url,
        params={"api-version": "2025-11-01-preview"},
        headers=headers,
        json=body
    )

    return func.HttpResponse(
        response.text,
        status_code=response.status_code,
        mimetype="application/json"
    )
```

### パターン2: FastAPI

```python
from fastapi import FastAPI, Request, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import msal
import requests
import os

app = FastAPI()
security = HTTPBearer()

def exchange_token_for_search(easyauth_token: str) -> str:
    """同上"""
    # ... (上記と同じ実装)

@app.post("/search")
async def search(
    request: Request,
    query: str,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    # EasyAuthトークンを取得
    easyauth_token = request.headers.get("X-MS-TOKEN-AAD-ACCESS-TOKEN")
    if not easyauth_token:
        easyauth_token = credentials.credentials

    # Search用トークンに交換
    search_user_token = exchange_token_for_search(easyauth_token)

    # サービストークン取得
    from azure.identity import DefaultAzureCredential
    credential = DefaultAzureCredential()
    service_token = credential.get_token("https://search.azure.com/.default").token

    # Azure AI Searchクエリ
    search_url = f"{os.getenv('SEARCH_SERVICE_ENDPOINT')}/indexes/{os.getenv('SEARCH_INDEX_NAME')}/docs/search"
    headers = {
        "Authorization": f"Bearer {service_token}",
        "x-ms-query-source-authorization": f"Bearer {search_user_token}",
        "Content-Type": "application/json"
    }

    body = {
        "search": query,
        "count": True,
        "vectorQueries": [{
            "kind": "text",
            "text": query,
            "fields": "snippet_vector"
        }],
        "queryType": "semantic",
        "semanticConfiguration": "semantic-configuration",
        "captions": "extractive",
        "answers": "extractive|count-3",
        "queryLanguage": "ja-jp"
    }

    response = requests.post(
        search_url,
        params={"api-version": "2025-11-01-preview"},
        headers=headers,
        json=body
    )

    return response.json()
```

---

## 【追加】Managed Identity フェデレーション（Workload Identity Federation）によるトークン交換（Python）

### 概要

従来の「サービスプリンシパルのシークレット」や「証明書」ではなく、**マネージドIDのフェデレーション（Workload Identity Federation）** を使ってMSALでトークン交換が可能です。これにより、シークレットレスで安全な認証が実現できます。

### 公式ドキュメント

- [Workload identity federation (MSAL.NET)](https://learn.microsoft.com/entra/msal/dotnet/acquiring-tokens/web-apps-apis/workload-identity-federation)
- [MSAL Python Managed Identity](https://learn.microsoft.com/entra/msal/python/advanced/managed-identity#examples)

### Pythonサンプル（Managed Identity経由でトークン取得）

```python
import msal
import requests

# System-assigned Managed Identity
managed_identity = msal.SystemAssignedManagedIdentity()
app = msal.ManagedIdentityClient(managed_identity)
result = app.acquire_token_for_client(resource='https://search.azure.com')
if "access_token" in result:
    print("Token obtained!", result["access_token"])
else:
    print("Failed to obtain token", result)
```

# User-assigned Managed Identity の場合は `msal.UserAssignedManagedIdentity(client_id=...)` などを利用

### ポイント

- Azure上（App Service, VM, Functions等）で動作している場合、**DefaultAzureCredential** でも同様にマネージドIDでトークン取得可能
- サービスプリンシパルのシークレットや証明書を一切使わず、Azureリソースの割り当てIDのみで安全に認証
- Workload Identity FederationをEntra IDアプリ登録で有効化し、必要に応じてFederated Credentialを追加

---

## 5. EasyAuthの設定

Azure Portal > App Service > 認証

1. **認証プロバイダー** として **Microsoft** を選択
2. **クライアントID** に上記のAzure ADアプリのクライアントIDを設定
3. **クライアントシークレット** を設定
4. **許可されたトークン対象ユーザー** に `api://<your-client-id>` を追加（オプション）
5. **トークンストア** を有効化
6. **認証されていない要求** を適切に設定（例: ログインを要求）

## 6. トークンフローの全体像

```
1. ユーザー → App Service (EasyAuth)
   ↓
   EasyAuthが認証してトークン発行（Microsoft Entra ID）

2. App Service → Azure Function/API
   ↓
   X-MS-TOKEN-AAD-ACCESS-TOKENヘッダーにトークン付与

3. Azure Function → Microsoft Entra ID (OBO Flow)
   ↓
   EasyAuthトークンをSearch用トークンに交換
   POST https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token
   {
     "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
     "assertion": "<easyauth_token>",
     "scope": "https://search.azure.com/.default",
     "client_id": "<client_id>",
     "client_secret": "<client_secret>"
   }

4. Azure Function → Azure AI Search
   ↓
   Authorization: Bearer <service_token>
   x-ms-query-source-authorization: Bearer <user_search_token>
```

## 7. トラブルシューティング

### エラー: "AADSTS65001: The user or administrator has not consented"

→ API権限で管理者の同意を与える必要があります

### エラー: "AADSTS50013: Assertion audience claim does not match"

→ EasyAuthで発行されたトークンのaudienceが正しくない可能性があります。App Serviceの認証設定を確認

### エラー: "Unauthorized"

→ Search用トークンのスコープまたは権限が不足している可能性があります

### トークンの確認方法

```python
import jwt
import json

# トークンをデコード（検証なし、デバッグ用のみ）
decoded = jwt.decode(easyauth_token, options={"verify_signature": False})
print(json.dumps(decoded, indent=2))

# 確認すべき項目:
# - "aud": audience（対象）
# - "scp": scopes（スコープ）
# - "oid": ユーザーオブジェクトID
# - "groups": グループID（必要な場合）
```

## 8. セキュリティベストプラクティス

1. **クライアントシークレットはKey Vaultに保存**

   ```python
   from azure.keyvault.secrets import SecretClient
   from azure.identity import DefaultAzureCredential

   credential = DefaultAzureCredential()
   secret_client = SecretClient(
       vault_url="https://<your-keyvault>.vault.azure.net/",
       credential=credential
   )
   client_secret = secret_client.get_secret("AZURE-CLIENT-SECRET").value
   ```

2. **トークンをキャッシュ（オプション）**
   - MSALライブラリは自動的にトークンキャッシュを提供

3. **最小権限の原則**
   - アプリケーションには必要最小限のAPI権限のみを付与

4. **監査ログの有効化**
   - Azure Entra IDのサインインログとアプリケーションログを監視

## 9. 参考リンク

- [Microsoft Authentication Library (MSAL) for Python](https://github.com/AzureMCP/microsoft-authentication-library-for-python)
- [On-Behalf-Of flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-on-behalf-of-flow)
- [Azure AI Search - Document-level security](https://learn.microsoft.com/en-us/azure/search/search-security-trimming-for-azure-search-with-aad)
