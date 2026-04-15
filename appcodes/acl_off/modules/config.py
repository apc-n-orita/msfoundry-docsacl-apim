import os
import sys
from dataclasses import dataclass


@dataclass
class AppConfig:
    """アプリケーション設定"""
    project_endpoint: str
    agent_name: str
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
        agent_name=os.getenv("AGENT_NAME"),
        project_appins_connection_name=os.getenv("PROJECT_APPINS_CONNECTION_NAME", "appi-connection")
    )


def validate_env_vars():
    """環境変数の検証"""
    required_vars = {
        "PROJECT_ENDPOINT": "Azure AI Project endpoint URL",
        "AGENT_NAME": "エージェント名",
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
