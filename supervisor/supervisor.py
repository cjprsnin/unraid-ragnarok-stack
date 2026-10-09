#!/usr/bin/env python3
"""Optional, advisory-only log summarizer. It never executes game commands."""
import json
import os
import time
import urllib.request
from pathlib import Path

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://YOUR_OLLAMA_HOST:11434").rstrip("/")
MODEL = os.getenv("OLLAMA_MODEL", "qwen3:4b")
LOG_DIR = Path(os.getenv("LOG_DIR", "/logs"))
REPORT_DIR = Path(os.getenv("REPORT_DIR", "/reports"))
INTERVAL = max(60, int(os.getenv("SCAN_INTERVAL_SECONDS", "900")))

def ask_ollama(text: str) -> str:
    payload = json.dumps({
        "model": MODEL,
        "prompt": "Summarize these Ragnarok server log lines. Identify likely errors and safe diagnostic suggestions. Do not propose executing commands automatically.\n\n" + text[-12000:],
        "stream": False,
        "think": False,
    }).encode()
    request = urllib.request.Request(
        OLLAMA_URL + "/api/generate", data=payload,
        headers={"Content-Type": "application/json"}, method="POST"
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        result = json.load(response)
    return str(result.get("response", ""))

def main():
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    if "YOUR_OLLAMA_HOST" in OLLAMA_URL:
        raise SystemExit("Set OLLAMA_URL to your existing Ollama endpoint before enabling the supervisor profile.")
    while True:
        try:
            candidates = sorted(
                (p for p in LOG_DIR.rglob("*") if p.is_file()),
                key=lambda p: p.stat().st_mtime, reverse=True
            )[:5]
            for path in candidates:
                try:
                    content = path.read_text(errors="replace")[-12000:]
                    if not content.strip():
                        continue
                    report = ask_ollama(content)
                    target = REPORT_DIR / (path.name + ".analysis.json")
                    target.write_text(json.dumps({
                        "source_file": path.name,
                        "generated_at": int(time.time()),
                        "model": MODEL,
                        "analysis": report,
                    }, indent=2))
                except Exception as exc:
                    print(f"Could not analyze {path.name}: {exc}", flush=True)
        except Exception as exc:
            print(f"Supervisor scan failed: {exc}", flush=True)
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()
