import msal


# ユーザーの同意が必要とエラーが出る場合、https://login.microsoftonline.com/<tenant_id>/oauth2/v2.0/authorize?client_id=<client_id>&response_type=code&redirect_uri=http://localhost&scope=api://<client_id>/user_impersonation https://search.azure.com/user_impersonation にブラウザでアクセスして同意を与える必要があります
def exchange_token_for_search(
    user_assertion: str,
    client_id: str,
    client_secret: str,
    tenant_id: str
) -> str:
    """On-Behalf-OfフローでAzure AI Search用トークンに交換"""
    authority = f"https://login.microsoftonline.com/{tenant_id}"
    app = msal.ConfidentialClientApplication(
        client_id=client_id,
        client_credential=client_secret,
        authority=authority
    )
    
    result = app.acquire_token_on_behalf_of(
        user_assertion=user_assertion,
        scopes=["https://search.azure.com/user_impersonation"]
    )
    
    if "access_token" in result:
        return result["access_token"]
    else:
        error = result.get("error")
        error_description = result.get("error_description")
        raise Exception(f"トークン交換失敗: {error} - {error_description}")

def try_get_usage_tokens(obj, keys):
    """usageオブジェクトから各種トークン数を堅牢に取り出すヘルパー"""
    for k in keys:
        if isinstance(obj, dict) and k in obj:
            return obj[k]
        if hasattr(obj, k):
            return getattr(obj, k)
    return None
