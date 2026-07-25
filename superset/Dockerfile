FROM apache/superset:4.1.1

USER root
RUN pip install --no-cache-dir clickhouse-connect gevent
USER superset

HEALTHCHECK --interval=15s --timeout=10s --start-period=180s --retries=20 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8088/health',timeout=8).status==200 else 1)"