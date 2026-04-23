# Azure AI Foundry マルチエージェント構成ナレッジ

## 1. A2A（Agent-to-Agent）プロトコルとは

A2A はエージェント間通信のオープンプロトコル（Google 主導）。ベンダーを問わずエージェントが相互通信できる。

### A2A の仕様

| 要素 | 内容 |
|------|------|
| Agent Card パス | `GET /.well-known/agent-card.json` |
| メッセージ受信 | `POST /v1/message:stream` |
| プロトコル | REST + SSE（Server-Sent Events）ストリーミング |
| メッセージ形式 | `parts` 配列内に `{"kind": "text", "text": "..."}` |

### Agent Card の最小構成

```json
{
  "name": "エージェント名",
  "description": "説明",
  "version": "1.0",
  "url": "https://your-server.example.com",
  "capabilities": {
    "streaming": true,
    "pushNotifications": false
  }
}
```

### A2A メッセージ受信エンドポイント（Python / FastAPI）

```python
@app.post("/v1/message:stream")
async def handle_message(body: dict):
    parts = body["message"].get("parts", [])
    user_text = next((p["text"] for p in parts if p.get("kind") == "text"), "")
    context_id = body["message"].get("contextId", "")

    def generate():
        for event in stream_response:
            if event.type == "response.output_text.delta":
                chunk = {
                    "kind": "message",
                    "role": "agent",
                    "parts": [{"kind": "text", "text": event.delta}],
                    "contextId": context_id,
                }
                yield f"data: {json.dumps(chunk, ensure_ascii=False)}\n\n"

    return StreamingResponse(generate(), media_type="text/event-stream")
```

---

## 2. Foundry Agent を A2A として公開する場合

Foundry Agent Service は A2A エンドポイントをネイティブに公開しない。外部サーバー（FastAPI 等）を自前で立てる必要がある。

### Foundry Agent の呼び出し方（Responses API）

```python
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

project = AIProjectClient(
    endpoint="<PROJECT_ENDPOINT>",
    credential=DefaultAzureCredential(),
)
openai_client = project.get_openai_client()

stream_response = openai_client.responses.create(
    stream=True,
    input=user_text,
    extra_body={
        "agent_reference": {
            "name": "<AGENT_NAME>",
            "type": "agent_reference"
        }
    },
)
```

> **注意**: `AIProjectClient.from_connection_string()` は非推奨。`AIProjectClient(endpoint=..., credential=...)` を使う。

---

## 3. A2A を使うべき場面・使わなくていい場面

| 場面 | 推奨 |
|------|------|
| 別テナント・別組織・別ベンダーのエージェントを呼ぶ | ✅ A2A |
| 異なる LLM バックエンド（他社製）と連携 | ✅ A2A |
| 外部にエージェントを公開・販売する | ✅ A2A |
| **同一 Foundry プロジェクト内のエージェントを呼ぶ** | ❌ A2A 不可・不要 |

> **重要**: 同一 Foundry プロジェクト内のエージェントは公開 A2A エンドポイントを持たないため、A2A ツールは使用不可。

---

## 4. 同一プロジェクト内のマルチエージェント構成（3パターン）

### パターン A：Connected Agents（Foundry Agent SDK）

既存のエージェントを `ConnectedAgentTool` でサブエージェントとして紐づける。

```python
from azure.ai.projects import AIProjectClient
from azure.ai.agents.models import ConnectedAgentTool
from azure.identity import DefaultAzureCredential

client = AIProjectClient(
    endpoint="<PROJECT_ENDPOINT>",
    credential=DefaultAzureCredential(),
)

connected_agent = ConnectedAgentTool(
    id="<サブエージェントのID>",
    name="sub_agent",
    description="専門タスクを担当するエージェント"
)

main_agent = client.agents.create_agent(
    model="<MODEL_DEPLOYMENT_NAME>",
    name="orchestrator",
    instructions="専門的な質問は sub_agent に委譲してください。",
    tools=connected_agent.definitions,
)
```

**制約**: サブエージェントの深さは最大 2 階層まで。

---

### パターン B：Agent Framework（Microsoft Agent Framework 1.0）の FoundryAgent

既存エージェントを `FoundryAgent` でラップし、`WorkflowBuilder` に組み込む。

```python
from agent_framework import WorkflowBuilder
from agent_framework.foundry import FoundryChatClient, FoundryAgent
from azure.identity import AzureCliCredential

# 既存エージェントをラップ
existing_agent = FoundryAgent(
    project_endpoint="<PROJECT_ENDPOINT>",
    agent_name="<AGENT_NAME>",
    agent_version="1.0",
    credential=AzureCliCredential(),
)

# 新規エージェント（オーケストレーター）
orchestrator = FoundryChatClient(
    project_endpoint="<PROJECT_ENDPOINT>",
    model="<MODEL>",
    credential=AzureCliCredential(),
).as_agent(
    name="Orchestrator",
    instructions="ユーザーの質問を整理して次のエージェントに渡す。",
)

# Sequential Workflow
workflow = (
    WorkflowBuilder(start_executor=orchestrator)
    .add_edge(orchestrator, existing_agent)
    .build()
)

async for update in workflow.run(message="質問", stream=True):
    if update.text:
        print(update.text, end="", flush=True)
```

---

### パターン C：Foundry ポータルの Visual Workflow（ノーコード）

ポータルの **Workflow** メニューから「+」→「Invoke agent」→ 既存エージェント名で検索して追加。Sequential / Group Chat / Human-in-the-loop のテンプレートあり。

---

## 5. Microsoft Agent Framework 1.0 と Semantic Kernel の違い

| 項目 | Microsoft Agent Framework 1.0 | Semantic Kernel |
|------|-------------------------------|-----------------|
| パッケージ | `agent-framework`, `agent-framework-foundry` | `semantic-kernel` |
| 位置づけ | AutoGen + SK の後継・統合（2026 年 GA） | 先代フレームワーク |
| Foundry クライアント | `FoundryChatClient` | `AzureAIAgent.create_client()` |
| エージェント作成 | `client.as_agent()` / `FoundryAgent()` | `AzureAIAgent()` |
| ツール定義 | `@tool` | `@kernel_function` |
| ワークフロー | `WorkflowBuilder` / `SequentialBuilder` | `AgentGroupChat`（旧） |
| 既存エージェント参照 | `FoundryAgent(agent_name=...)` | `client.agents.get_agent(assistant_id=...)` |

> Agent Framework 1.0 が現時点での推奨。Semantic Kernel からのマイグレーションガイドあり。

---

## 6. Agent Framework のワークフローパターン

| パターン | クラス | 用途 |
|---------|--------|------|
| Sequential | `SequentialBuilder` / `WorkflowBuilder.add_edge()` | A → B → C の順に処理 |
| Concurrent | `ConcurrentBuilder` | 複数エージェントを並列実行して結果を集約 |
| Group Chat | `GroupChatBuilder` | オーケストレーターがスピーカーを動的に選択 |
| Handoff | `HandoffBuilder` | エージェントが別エージェントにタスクを完全委譲 |
| Human-in-the-loop | `@tool(approval_mode="always_require")` | 人間の承認を挟む |

---

## 7. A2A エージェントの Container Apps デプロイ時の注意

- `AGENT_BASE_URL` には末尾スラッシュなしで設定する
  - ✅ `https://your-app.japaneast.azurecontainerapps.io`
  - ❌ `https://your-app.japaneast.azurecontainerapps.io/`
- Agent Card の `url` フィールドに設定するベース URL であり、呼び出し元がこれをもとに `/v1/message:stream` を構築する

---

## 参考リンク

- [A2A プロトコル仕様](https://a2a-protocol.org/latest/)
- [Microsoft Agent Framework ドキュメント](https://learn.microsoft.com/agent-framework/overview/)
- [Agents in Workflows](https://learn.microsoft.com/agent-framework/workflows/agents-in-workflows)
- [Connected Agents](https://learn.microsoft.com/azure/ai-foundry/agents/how-to/connected-agents)
- [Add an A2A agent endpoint to Foundry Agent Service](https://learn.microsoft.com/azure/ai-foundry/agents/how-to/tools/agent-to-agent)
