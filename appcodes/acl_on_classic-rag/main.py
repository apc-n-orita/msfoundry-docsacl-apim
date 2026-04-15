import os
import sys
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient
from opentelemetry import trace
import modules

def main():
    # 1. 初期準備
    modules.validate_env_vars()

    # 環境変数の取得
    config = modules.load_config()

    try:
        credential = DefaultAzureCredential()
        # 2. プロジェクト接続 & テレメトリ      
        project_client = AIProjectClient(endpoint=config.project_endpoint, credential=credential)
        conn = project_client.connections.get(name=config.project_appins_connection_name, include_credentials=True)
        tracer = modules.setup_telemetry(conn.credentials.api_key, credential)

        # 3. 認証 (OBOトークン)
        print(f"\nAzure AI Search 用トークン取得中（OBOフロー）...")
        user_token = modules.exchange_token_for_search(
            user_assertion=credential.get_token(f"api://{config.client_id}/.default").token,
            client_id=config.client_id,
            client_secret=config.client_secret,
            tenant_id=config.tenant_id
        )

        # 4. クライアント生成
        openai_client, search_client, http_client = modules.create_openai_ais_client(config.openai_endpoint, config.search_endpoint, config.index_name, credential)

        # 6. 対話実行
        with tracer.start_as_current_span("knowledge-classic-rag-session"):
            modules.run_chat_loop(
                openai_client, search_client, user_token, credential, tracer, config.model_deployment, http_client
            )

    except Exception as e:
        print(f"❌ 起動エラー: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        if 'http_client' in locals():
            print("\nHTTPクライアントを閉じています...")
            http_client.close()
        print("トレーサーをシャットダウンしています...")
        trace.get_tracer_provider().shutdown()

if __name__ == "__main__":
    main()
