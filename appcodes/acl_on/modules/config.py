import os
import sys
from dataclasses import dataclass


@dataclass
class AppConfig:
    """アプリケーション設定"""
    project_endpoint: str
    model_deployment: str
    kb_mcp_url: str
    project_ais_connection_name: str
    client_id: str
    client_secret: str
    tenant_id: str
    project_appins_connection_name: str


def load_config() -> AppConfig:
    """
    環境変数からアプリケーション設定を取得
    
    Returns:
        AppConfig: アプリケーション設定
    """
    validate_env_vars()
    return AppConfig(
        project_endpoint=os.getenv("PROJECT_ENDPOINT"),
        model_deployment=os.getenv("MODEL_DEPLOYMENT"),
        kb_mcp_url=os.getenv("KB_MCP_URL"),
        project_ais_connection_name=os.getenv("PROJECT_AIS_CONNECTION_NAME"),
        client_id=os.getenv("AZURE_OBO_CLIENT_ID"),
        client_secret=os.getenv("AZURE_OBO_CLIENT_SECRET"),
        tenant_id=os.getenv("AZURE_OBO_TENANT_ID"),
        project_appins_connection_name=os.getenv("PROJECT_APPINS_CONNECTION_NAME", "appi-connection")
    )


def validate_env_vars():
    """環境変数の検証"""
    required_vars = {
        "PROJECT_ENDPOINT": "Azure AI Project endpoint URL",
        "MODEL_DEPLOYMENT": "使用するモデルのデプロイ名",
        "KB_MCP_URL": "Knowledge Base MCP サーバー URL",
        "PROJECT_AIS_CONNECTION_NAME": "Foundry IQ への接続名",
        "AZURE_OBO_CLIENT_ID": "Azure ADアプリケーションのクライアントID (OBOフロー用)",
        "AZURE_OBO_CLIENT_SECRET": "Azure ADアプリケーションのクライアントシークレット (OBOフロー用)",
        "AZURE_OBO_TENANT_ID": "Azure ADテナントID (OBOフロー用)",
        "OTEL_SERVICE_NAME": "OpenTelemetry Service Name (分散トレース用)"
    }
    missing_vars = []
    for var, description in required_vars.items():
        if not os.getenv(var):
            missing_vars.append(f" {var}: {description}")
    if missing_vars:
        print("❌ 必須の環境変数が設定されていません:", file=sys.stderr)
        for var in missing_vars:
            print(var, file=sys.stderr)
        sys.exit(1)
