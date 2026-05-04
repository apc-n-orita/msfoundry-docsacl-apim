import httpx
from opentelemetry import trace
from opentelemetry.propagate import inject
from azure.monitor.opentelemetry import configure_azure_monitor

def inject_traceparent(request: httpx.Request):
    """OpenTelemetry propagatorでTraceContextをリクエストヘッダーに注入"""
    inject(request.headers)

def setup_telemetry(connection_string, credential):
    """Azure Monitor (OpenTelemetry) の初期化"""
    configure_azure_monitor(
        connection_string=connection_string,
        credential=credential
    )
    return trace.get_tracer(__name__)
