import os
import sys
import httpx
import unicodedata
import jwt
from openai import AzureOpenAI
from azure.search.documents import SearchClient
from azure.search.documents.models import VectorizableTextQuery
from azure.identity import get_bearer_token_provider
from azure.core.exceptions import HttpResponseError
from opentelemetry.trace import Status, StatusCode
from .telemetry_utils import inject_traceparent
from .auth_utils import record_tokens_to_span

def create_openai_ais_client(openai_endpoint, search_endpoint, index_name, credential):
    """クライアントの初期化"""
    http_client = httpx.Client(event_hooks={"request": [inject_traceparent]})
    
    # Azure OpenAI用トークンプロバイダー
    openai_token_provider = get_bearer_token_provider(
        credential, 
        "https://cognitiveservices.azure.com/.default"
    )
    
    # Azure OpenAI クライアント
    openai_client = AzureOpenAI(
        azure_endpoint=openai_endpoint,
        azure_ad_token_provider=openai_token_provider,
        api_version="2024-02-15-preview",
        http_client=http_client
    )
    
    # Search クライアント
    search_client = SearchClient(
        endpoint=search_endpoint,
        index_name=index_name,
        credential=credential,
        api_version="2025-11-01-preview",
        http_client=http_client
    )

    return openai_client, search_client, http_client

def run_chat_loop(openai_client, search_client, user_token, credential, tracer, model_deployment, http_client):
    """対話メインループ"""
    print(f"=== AIモデル情報 ===")
    print(f"Model: {model_deployment}")
    print("\n" + "="*60)
    print("対話を開始します。終了するには 'exit', 'quit', 'q' を入力してください。")
    print("="*60)

    decoded = jwt.decode(user_token, options={"verify_signature": False})
    user_groups = decoded.get("groups", [])

    if user_groups:
        group_ids_str = ",".join(user_groups)
        security_filter = f"GroupIds/any(g: search.in(g, '{group_ids_str}'))"
    else:
        security_filter = "GroupIds/any(g: g eq 'everyone')"

    while True:
        try:
            print("\n質問を入力してください:")

            user_input = input("ユーザー: ").strip()
            # 全角英数字・記号を半角に変換（日本語はそのまま）
            def to_halfwidth(s):
                return unicodedata.normalize('NFKC', s)
            user_input = to_halfwidth(user_input)

            if user_input.lower() in ["exit", "quit", "q"]:
                print("\n対話を終了します。")
                break
            if not user_input:
                continue

            with tracer.start_as_current_span("user_chat_turn") as span:
                span.set_attribute("gen_ai.prompt", user_input)
                span.set_attribute("model_deployment", model_deployment)

                try:
                    # 1. 検索クエリの生成 (RAG用キーワード抽出)
                    print(f"\n=== 検索クエリ生成中 ===")
                    
                    keyword_completion = openai_client.chat.completions.create(
                        model=model_deployment,
                        messages=[
                            {"role": "system", "content": "あなたは検索用のクエリを作るAIです。キーワードのみを出力してください。"},
                            {"role": "user", "content": user_input}
                        ],
                        max_tokens=64,
                        temperature=0.2
                    )
                    # トークン使用量の記録
                    record_tokens_to_span(span, keyword_completion.usage, "query_tokens")
                    
                    search_text = keyword_completion.choices[0].message.content.strip()

                    # 3. Azure AI Search での検索実行
                    print(f"=== 検索実行中: '{search_text}' ===")
                    results = search_client.search(
                        search_text=search_text,
                        filter=security_filter,
                        query_type="semantic",
                        semantic_configuration_name="tartalia-semantic-configuration",
                        vector_queries=[
                            VectorizableTextQuery(
                                text=search_text,
                                fields="snippet_vector",
                                k_nearest_neighbors=3
                            )
                        ],
                        headers={"x-ms-enable-elevated-read": "true"}
                    )

                    # 検索結果からスニペットを抽出
                    snippets = []
                    for result in results:
                        captions = result.get("@search.captions")
                        if captions:
                            for caption in captions[:3]:
                                snippets.append(caption.text)
                        else:
                            content = result.get("snippet")
                            if content:
                                snippets.append(content[:500])

                    if not snippets:
                        print("⚠️ 該当するドキュメントが見つかりませんでした。")
                        continue

                    # 4. 最終的な回答生成
                    print(f"=== 回答生成中 ===")
                    summary_prompt = (
                        "以下のドキュメント抜粋を元に、ユーザーの質問に答えてください。\n"
                        f"質問: {user_input}\n\n"
                        "--- ドキュメント抜粋 ---\n"
                    )
                    for i, s in enumerate(snippets, 1):
                        summary_prompt += f"[{i}]: {s}\n"

                    summary_completion = openai_client.chat.completions.create(
                        model=model_deployment,
                        messages=[
                            {"role": "system", "content": "あなたは信頼性の高い要約アシスタントです。"},
                            {"role": "user", "content": summary_prompt}
                        ],
                        max_tokens=800,
                        temperature=0.3
                    )

                    # 回答の表示
                    answer = summary_completion.choices[0].message.content
                    print("\n=== 検索結果に基づく回答 ===\n")
                    print(answer)

                    # 5. トークン使用量の詳細をSpanに記録
                    record_tokens_to_span(span, summary_completion.usage, "res_tokens")

                except HttpResponseError as e:
                    span.set_status(Status(StatusCode.ERROR, str(e)))
                    span.record_exception(e)
                    print(f"\n❌ APIエラー: {e.status_code} - {e.message}", file=sys.stderr)
                    continue

        except KeyboardInterrupt:
            print("\nユーザーにより中断されました。")
            break
        except Exception as e:
            print(f"\n❌ 致命的なエラー: {type(e).__name__}: {e}", file=sys.stderr)
            break
