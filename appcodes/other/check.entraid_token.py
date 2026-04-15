import sys
import json
import base64
import os
import requests
from azure.identity import DefaultAzureCredential

# AUDを環境変数から取得
aud = os.environ.get("AUD")
if not aud:
    print("[ERROR] AUDの環境変数を設定してください。", file=sys.stderr)
    sys.exit(1)

credential = DefaultAzureCredential()
scope = f"{aud}.default"
token = credential.get_token(scope).token
parts = token.split('.')
if len(parts) >= 2:
    # パディング調整
    payload = parts[1]
    padding = 4 - len(payload) % 4
    if padding != 4:
        payload += '=' * padding
    decoded = base64.urlsafe_b64decode(payload)
    claims = json.loads(decoded)
    print('=== Token Claims ===')
    print(json.dumps(claims, indent=2, ensure_ascii=False))
