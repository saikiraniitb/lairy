#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import traceback

from needle_intent import NeedleIntentEngine


def emit(value: dict) -> None:
    sys.stdout.write(json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def main() -> int:
    engine = NeedleIntentEngine()
    emit({"type": "ready", "parser": "needle2-base", "load_ms": engine.load_ms})
    for line in sys.stdin:
        try:
            request = json.loads(line)
            request_id = request.get("id")
            text = request.get("text")
            if not isinstance(text, str) or not text.strip():
                raise ValueError("text must be a non-empty string")
            result = engine.parse(text)
            emit({"id": request_id, "ok": True, **result})
        except Exception as error:  # Keep the warm helper alive after malformed requests.
            emit({
                "id": locals().get("request", {}).get("id") if isinstance(locals().get("request"), dict) else None,
                "ok": False,
                "error": str(error),
                "debug_error": traceback.format_exc(),
            })
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
