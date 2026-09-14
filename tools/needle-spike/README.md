# IntentOS Needle 2 feasibility spike

This isolated experiment evaluates the current official Needle 2 base model before any Swift
integration or fine-tuning. It declares exactly three tools: `remember`, `do`, and `follow_up`.

## Setup

```bash
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/needle fetch --generation 2 --out runtime
```

The first run downloads the official generation-2 engine. Telemetry is disabled by both
`NEEDLE_TELEMETRY=0` and `DO_NOT_TRACK=1` before Needle is imported.

## Run

```bash
.venv/bin/python benchmark.py
```

Outputs are written beside the scripts:

- `needle_benchmark.jsonl`: one complete record per utterance
- `needle_benchmark_summary.md`: aggregate metrics, threshold analysis, and failure cases

The benchmark keeps one agent warm and calls `reset()` between independent utterances. Model load
time is reported separately from warm inference latency.

## Helper protocol

`helper.py` is the prototype production bridge. It keeps Needle warm and exchanges one compact JSON
object per line over stdin/stdout:

```json
{"id":"request-id","text":"Review PR 182 tomorrow.","current_date":"2026-09-14"}
```

It never opens a network listener. Diagnostics emitted by the native runtime are redirected away
from protocol stdout.
