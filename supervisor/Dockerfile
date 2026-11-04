FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN useradd --system --create-home --home-dir /app supervisor
WORKDIR /app
COPY --chown=supervisor:supervisor supervisor.py /app/supervisor.py
COPY --chmod=755 entrypoint.sh /usr/local/bin/supervisor-entrypoint
# The entrypoint starts as root only to fix report-dir ownership, then drops to a
# non-root uid/gid with setpriv (util-linux, already in the base image).
ENTRYPOINT ["/usr/local/bin/supervisor-entrypoint"]
CMD ["python", "/app/supervisor.py"]
