#!/usr/bin/env python3
"""Minimal development proxy that keeps the OpenAI API key out of the iOS app."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
MAX_REQUEST_BYTES = 40 * 1024 * 1024
UPSTREAM_BASE_URL = "https://api.openai.com/v1"


def load_env(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key:
            os.environ.setdefault(key, value)


load_env(ROOT / ".env")


class ProxyHandler(BaseHTTPRequestHandler):
    server_version = "RememberOpenAIProxy/1.0"

    def do_GET(self) -> None:
        if self.path != "/health":
            self.send_error(404)
            return
        self._send_json(
            200,
            {
                "status": "ok",
                "configured": bool(os.environ.get("OPENAI_API_KEY")),
                "model": os.environ.get("OPENAI_MODEL", "gpt-5.5"),
            },
        )

    def do_POST(self) -> None:
        routes = {
            "/v1/responses": ("responses", "OPENAI_MODEL", "gpt-5.5"),
            "/v1/embeddings": ("embeddings", "OPENAI_EMBEDDING_MODEL", "text-embedding-3-small"),
        }
        route = routes.get(self.path)
        if route is None:
            self.send_error(404)
            return

        api_key = os.environ.get("OPENAI_API_KEY", "").strip()
        if not api_key:
            self._send_json(503, {"error": {"message": "OPENAI_API_KEY is not configured"}})
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_error(400)
            return
        if content_length <= 0 or content_length > MAX_REQUEST_BYTES:
            self._send_json(413, {"error": {"message": "Request body is empty or too large"}})
            return

        try:
            payload = json.loads(self.rfile.read(content_length))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self._send_json(400, {"error": {"message": "Request body must be valid JSON"}})
            return
        if not isinstance(payload, dict):
            self._send_json(400, {"error": {"message": "Request body must be a JSON object"}})
            return

        upstream_path, model_key, default_model = route
        payload["model"] = os.environ.get(model_key, default_model)
        request = urllib.request.Request(
            f"{UPSTREAM_BASE_URL}/{upstream_path}",
            data=json.dumps(payload, separators=(",", ":")).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                self._send_bytes(response.status, response.read(), "application/json")
        except urllib.error.HTTPError as error:
            self._send_bytes(error.code, error.read(), "application/json")
        except urllib.error.URLError:
            self._send_json(502, {"error": {"message": "Could not reach the OpenAI API"}})

    def log_message(self, format: str, *args: Any) -> None:
        # Log method/path/status only. Request bodies and credentials are never logged.
        sys.stderr.write("%s - %s\n" % (self.address_string(), format % args))

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        self._send_bytes(status, json.dumps(payload).encode("utf-8"), "application/json")

    def _send_bytes(self, status: int, data: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main() -> None:
    host = os.environ.get("OPENAI_PROXY_HOST", "127.0.0.1")
    port = int(os.environ.get("OPENAI_PROXY_PORT", "8787"))
    server = ThreadingHTTPServer((host, port), ProxyHandler)
    print(f"Remember OpenAI proxy listening on http://{host}:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
