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

def record_tokens_to_span(span, usage, prefix):
    """usage情報をパースしてSpan属性にセットし、コンソールに表示するヘルパー関数"""
    if not usage:
        return

    # トークン数値の取得
    prompt_tokens = try_get_usage_tokens(usage, ['prompt_tokens'])
    completion_tokens = try_get_usage_tokens(usage, ['completion_tokens'])
    total_tokens = try_get_usage_tokens(usage, ['total_tokens'])

    # 詳細(キャッシュ/推論)の取得
    p_details = getattr(usage, 'prompt_tokens_details', None)
    c_details = getattr(usage, 'completion_tokens_details', None)
    cached_tokens = try_get_usage_tokens(p_details, ['cached_tokens'])
    reasoning_tokens = try_get_usage_tokens(c_details, ['reasoning_tokens'])

    # Span属性へのセット
    span.set_attribute(f"{prefix}.input", int(prompt_tokens or 0))
    span.set_attribute(f"{prefix}.output", int(completion_tokens or 0))
    span.set_attribute(f"{prefix}.total", int(total_tokens or 0))
    
    if cached_tokens:
        span.set_attribute(f"{prefix}.input.cached", int(cached_tokens))
    if reasoning_tokens:
        span.set_attribute(f"{prefix}.output.reasoning", int(reasoning_tokens))

    # コンソール出力
    label = "検索クエリ" if prefix == "query_tokens" else "回答生成"
    print(f"\n[{label}トークン統計]")
    print(f"  入力: {prompt_tokens} (キャッシュ: {cached_tokens})")
    print(f"  出力: {completion_tokens} (推論: {reasoning_tokens})")
    print(f"  合計: {total_tokens}")
