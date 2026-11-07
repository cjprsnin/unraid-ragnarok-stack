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
NEWEST_FILES = max(1, int(os.getenv("SCAN_NEWEST_FILES", "5")))
STATE_FILE_NAME = ".supervisor-state.json"

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

def load_state(path: Path) -> dict:
    """Return {relative_path: [mtime_ns, size]} for files already analyzed."""
    try:
        data = json.loads(path.read_text())
        return {str(k): list(v) for k, v in data.items() if isinstance(v, list) and len(v) == 2}
    except (OSError, ValueError, AttributeError):
        return {}

def write_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, path)

def report_path(report_dir: Path, relative: Path) -> Path:
    """Reports mirror the log tree, so same-named files in different folders cannot collide."""
    return report_dir / relative.parent / (relative.name + ".analysis.json")

def scan_once(log_dir: Path, report_dir: Path, state: dict, ask=ask_ollama, newest: int = NEWEST_FILES) -> bool:
    """Analyze the newest files that changed since their last successful analysis.

    Returns True when the state changed and should be saved.
    """
    files = {}
    for path in log_dir.rglob("*"):
        try:
            if path.is_file():
                st = path.stat()
                files[path] = (st.st_mtime_ns, st.st_size)
        except OSError:
            continue  # file vanished or unreadable between listing and stat

    changed = False
    present = {p.relative_to(log_dir).as_posix() for p in files}
    for key in [k for k in state if k not in present]:
        del state[key]  # forget deleted files so a recreated file is analyzed again
        changed = True

    for path, signature in sorted(files.items(), key=lambda item: item[1][0], reverse=True)[:newest]:
        relative = path.relative_to(log_dir)
        key = relative.as_posix()
        if state.get(key) == list(signature):
            continue  # unchanged since the last successful analysis
        try:
            content = path.read_text(errors="replace")[-12000:]
            if content.strip():
                report = ask(content)
                write_atomic(report_path(report_dir, relative), json.dumps({
                    "source_file": key,
                    "generated_at": int(time.time()),
                    "model": MODEL,
                    "analysis": report,
                }, indent=2))
            # Recorded with the stat taken BEFORE reading, so lines appended while
            # Ollama was thinking still trigger another analysis next cycle.
            state[key] = list(signature)
            changed = True
        except Exception as exc:
            print(f"Could not analyze {key}: {exc}", flush=True)  # not recorded: retried next cycle
    return changed

def main():
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    if "YOUR_OLLAMA_HOST" in OLLAMA_URL:
        raise SystemExit("Set OLLAMA_URL to your existing Ollama endpoint before enabling the supervisor profile.")
    state_file = REPORT_DIR / STATE_FILE_NAME
    state = load_state(state_file)
    while True:
        try:
            if scan_once(LOG_DIR, REPORT_DIR, state):
                write_atomic(state_file, json.dumps(state))
        except Exception as exc:
            print(f"Supervisor scan failed: {exc}", flush=True)
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()
