FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN useradd --system --create-home --home-dir /app supervisor
WORKDIR /app
COPY --chown=supervisor:supervisor supervisor.py /app/supervisor.py
USER supervisor
CMD ["python", "/app/supervisor.py"]
