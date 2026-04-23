import os
import sys
import httpx
import unicodedata
from openai import AzureOpenAI
from azure.identity import get_bearer_token_provider
from azure.core.exceptions import HttpResponseError
from .telemetry_utils import inject_traceparent
from datetime import datetime, timezone
from opentelemetry.trace import Status, StatusCode
from .auth_utils import try_get_usage_tokens


def to_halfwidth(s):
    return unicodedata.normalize('NFKC', s)


def create_openai_client(project_endpoint, credential):
    # httpxクライアントの構築
    http_client = httpx.Client(event_hooks={"request": [inject_traceparent]})
    
    # トークンプロバイダー
    token_provider = get_bearer_token_provider(
        credential, 
        "https://ai.azure.com/.default"
    )
    
    # AzureOpenAIクライアント
    client = AzureOpenAI(
        azure_endpoint=project_endpoint,
        azure_ad_token_provider=token_provider,
        api_version="2025-11-15-preview",
        http_client=http_client
    )
    return client, http_client


def run_chat_loop(openai_client, http_client, user_token, tracer, 
                  project_endpoint, model_deployment, kb_acl_mcp_url, project_connection_id):
    
    print(f"=== MS foundry 接続情報 ===")
    print(f"Project: {project_endpoint}")
    print(f"Model: {model_deployment}")
    
    previous_response_id = None
    
    print("\n" + "="*60)
    print("対話を開始します。終了するには 'exit', 'quit', 'q' を入力してください。")
    print("="*60)

    while True:
        try:
            print("\n質問を入力してください:")
            user_input = input("ユーザー: ").strip()
            user_input = to_halfwidth(user_input)

            if user_input.lower() in ["exit", "quit", "q"]:
                print("\n対話を終了します。")
                break
            if not user_input:
                continue

            print(f"\n=== クエリ送信中 ===")
            
            with tracer.start_as_current_span("user_chat_turn") as span:
                span.set_attribute("project_endpoint", project_endpoint)
                span.set_attribute("model_deployment", model_deployment)
                span.set_attribute("agent_name", "info-agent-tartaria-acl")
                span.set_attribute("gen_ai.prompt", user_input)

                mcp_tool = {
                    "type": "mcp",
                    "server_label": "kb_acl_test",
                    "server_url": kb_acl_mcp_url,
                    "project_connection_id": project_connection_id,
                    "require_approval": "never",
                    "allowed_tools": ["knowledge_base_retrieve"],
                    "headers": {"x-ms-query-source-authorization": user_token},
                }

                request_params = {
                    "model": model_deployment,
                    "input": user_input,
                    "tools": [mcp_tool],
                }

                if previous_response_id:
                    request_params["previous_response_id"] = previous_response_id
                    print(f"前回レスポンスID: {previous_response_id}")
                    span.set_attribute("conversation.previous_response_id", previous_response_id)
                else:
                    print("新しい会話を開始します")
                    span.set_attribute("conversation.is_new", True)

                # Cookieデバッグ（送信前）
                if http_client.cookies:
                    print(f"[DEBUG] 送信するCookie: {dict(http_client.cookies)}")
                else:
                    print(f"[DEBUG] Cookie未設定（初回リクエスト）")

                try:
                    response = openai_client.responses.create(**request_params)
                except HttpResponseError as e:
                    span.set_attribute("error_statuscode", str(e.status_code))
                    span.set_attribute("error_message", str(e.message))
                    span.set_attribute("error_type", type(e).__name__)
                    span.set_status(Status(StatusCode.ERROR, str(e)))
                    span.record_exception(e)
                    print(f"\n❌ HTTP エラー: {e.status_code} - {e.message}", file=sys.stderr)
                    continue
                except Exception as e:
                    span.set_attribute("error_message", str(e))
                    span.set_attribute("error_type", type(e).__name__)
                    span.set_status(Status(StatusCode.ERROR, str(e)))
                    span.record_exception(e)
                    print(f"\n❌ エラーが発生しました: {type(e).__name__}: {e}", file=sys.stderr)
                    break

                # Cookieデバッグ（受信後）
                if http_client.cookies:
                    print(f"[DEBUG] 受信後のCookie Jar: {dict(http_client.cookies)}")

                print(f"\n=== レスポンス ===")
                print(f"Status: {response.status}")
                print(f"Response ID: {response.id}")
                previous_response_id = response.id

                # 回答表示
                has_text_output = False
                if hasattr(response, 'output_text') and response.output_text:
                    print(f"\n回答:\n{response.output_text}")
                    has_text_output = True
                else:
                    for item in getattr(response, 'output', []):
                        if getattr(item, 'type', None) == 'text':
                            print(f"\n回答:\n{item.text}")
                            has_text_output = True
                
                if not has_text_output:
                    print("(回答が取得できませんでした)")

                # トークン使用量記録
                usage = getattr(response, 'usage', None)
                if usage:
                    # 詳細情報を抽出してSpan属性にセット
                    i_t = try_get_usage_tokens(usage, ['input_tokens', 'prompt_tokens'])
                    o_t = try_get_usage_tokens(usage, ['output_tokens', 'completion_tokens'])
                    t_t = try_get_usage_tokens(usage, ['total_tokens', 'total_text_tokens'])
                    span.set_attribute("tokens.input", int(i_t) if i_t else 0)
                    span.set_attribute("tokens.output", int(o_t) if o_t else 0)
                    span.set_attribute("tokens.total", int(t_t) if t_t else 0)
                    
                    # 以前のコードにあった詳細な内訳
                    i_det = getattr(usage, 'input_tokens_details', None)
                    o_det = getattr(usage, 'output_tokens_details', None)
                    cached = try_get_usage_tokens(i_det, ['cached_tokens'])
                    reasoning = try_get_usage_tokens(o_det, ['reasoning_tokens'])
                    if cached:
                        span.set_attribute("tokens.input.cached", int(cached))
                    if reasoning:
                        span.set_attribute("tokens.output.reasoning", int(reasoning))

                    print(f"\nトークン使用量: {usage}")

        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"❌ エラー: {e}")
            break
