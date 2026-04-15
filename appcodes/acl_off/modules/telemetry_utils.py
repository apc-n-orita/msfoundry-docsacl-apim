import httpx
from opentelemetry import trace
from azure.monitor.opentelemetry import configure_azure_monitor

def inject_traceparent(request: httpx.Request):
    """W3C TraceContext (traceparent) をリクエストヘッダーに注入"""
    current_span = trace.get_current_span()
    sc = current_span.get_span_context() if current_span else None
    if sc is not None and sc.is_valid:
        trace_id_hex = f"{sc.trace_id:032x}"
        span_id_hex  = f"{sc.span_id:016x}"
        request.headers["traceparent"] = f"00-{trace_id_hex}-{span_id_hex}-01"

def setup_telemetry(connection_string, credential):
    """Azure Monitor (OpenTelemetry) の初期化"""
    configure_azure_monitor(
        connection_string=connection_string,
        credential=credential
    )
    return trace.get_tracer(__name__)
