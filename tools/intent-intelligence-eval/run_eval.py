#!/usr/bin/env python3
"""
Intent Intelligence V1 (Gemini) evaluation harness.

Runs dataset.jsonl through the live Gemini structured-output endpoint using the SAME system
prompt and JSON Schema as Sources/OpenClip/Intent/GeminiIntentParser.swift (kept in sync by hand —
see the "KEEP IN SYNC" markers below), applies the same deterministic grounding + classification
logic as IntentGroundingValidator.swift / IntentClassifier.swift, and reports the metrics called
for in the Intent Intelligence V1 milestone.

This script never fabricates results: if no API key is configured, it exits with an explanatory
error rather than inventing numbers. Never commit real result numbers you have not actually
observed from a live run.

Usage:
    export GEMINI_API_KEY=...          # or store one via Preferences -> IntentOS -> Gemini API Key
    python3 tools/intent-intelligence-eval/run_eval.py [--model gemini-3.8-flash] [--limit N]

Never commit a real API key. This script only ever reads one — from the environment or from the
same ~/.openclip/secrets.json IntentOS itself uses — and never prints or logs it.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
DATASET_PATH = ROOT / "dataset.jsonl"
RESULTS_PATH = ROOT / "results.jsonl"
DOCS_PATH = ROOT.parent.parent / "docs" / "intentos" / "gemini-intelligence-eval.md"
SECRETS_PATH = Path.home() / ".openclip" / "secrets.json"
GEMINI_API_KEY_ACCOUNT = "intentGeminiAPIKey"
DEFAULT_MODEL = "gemini-3.8-flash"

# --- KEEP IN SYNC with GeminiIntentParser.swift's `systemPrompt` -----------------------------
SYSTEM_PROMPT = """You are IntentOS Intent Intelligence.

Your task is to determine whether explicitly selected text represents something the user should track, and to describe your understanding of it structurally. You never see anything the user did not explicitly select and capture.

Prefer NO_INTENT (hasTrackableIntent = false) over inventing an obligation. Never invent dates, deadlines, people, actions, resources, recipients, or triggers not clearly supported by the input text. Every date/time phrase, person name, or condition clause you report must be copied verbatim from the input -- never computed, resolved, or paraphrased. If the input has no such phrase, omit that field entirely.

Distinguish:
- actions the user must perform
- requests the user sent to others
- things the user is waiting for
- explicit information the user wants remembered
- non-actionable statements

Pay special attention to:
- who is speaking, and who owns the next action
- tense (past work is not trackable; only present/future/conditional obligations are)
- negation ("don't send this" is never a positive action)
- conditional language ("if Finance approves it, send the proposal")
- completed work ("I already sent it") -- not trackable
- third-party commitments ("Arun will send me the roadmap") -- never owned by the user
- requests and whether the user is the one asking or the one being asked
- direction: "incoming" means the text is addressed AT the reader (presumed to be the user) -- e.g. "Please review this", "Can you send me X" said BY someone else TO the user. "outgoing" means the text is the user's OWN words addressed to someone else -- e.g. "Can we have a session at 5pm?", "I'll send you the file." First-person subject pronouns ("I", "I'll", "I'm") without a direct question/request to the reader suggest outgoing/self; an imperative or a question with no first-person framing suggests incoming.
- whether a response/reply is expected at all

Return only structured data matching the provided schema."""

# --- KEEP IN SYNC with GeminiIntentParser.swift's `understandingSchema` ----------------------
UNDERSTANDING_SCHEMA: dict[str, Any] = {
    "type": "OBJECT",
    "properties": {
        "hasTrackableIntent": {"type": "BOOLEAN"},
        "speechAct": {"type": "STRING", "enum": ["request", "commitment", "reminder", "statement", "instruction", "question", "unknown"]},
        "direction": {"type": "STRING", "enum": ["incoming", "outgoing", "self", "unknown"]},
        "actor": {"type": "STRING", "enum": ["self", "other", "group", "unknown"]},
        "owner": {"type": "STRING", "enum": ["self", "other", "shared", "unknown"]},
        "requestedAction": {"type": "STRING", "nullable": True},
        "subject": {"type": "STRING", "nullable": True},
        "target": {"type": "STRING", "nullable": True},
        "requestedOutcome": {"type": "STRING", "nullable": True},
        "temporalState": {"type": "STRING", "enum": ["past", "present", "future", "conditional", "unknown"]},
        "polarity": {"type": "STRING", "enum": ["positive", "negative", "unknown"]},
        "commitmentStrength": {"type": "STRING", "enum": ["committed", "requested", "suggested", "possible", "unknown"]},
        "deadlineText": {"type": "STRING", "nullable": True},
        "trigger": {"type": "STRING", "nullable": True},
        "waitingFor": {"type": "STRING", "nullable": True},
        "responseExpected": {"type": "BOOLEAN", "nullable": True},
        "resourceLabels": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {"url": {"type": "STRING"}, "label": {"type": "STRING"}},
                "required": ["url", "label"],
            },
        },
        "confidence": {"type": "NUMBER", "nullable": True},
    },
    "required": ["hasTrackableIntent", "speechAct", "direction", "actor", "owner", "temporalState", "polarity", "commitmentStrength"],
}

URL_RE = re.compile(r"https?://[^\s<>\"']+")
KEYWORD_PHRASES = [
    "today", "tonight", "tomorrow", "yesterday", "next week", "next month", "this week", "this weekend",
    "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
    "next monday", "next tuesday", "next wednesday", "next thursday", "next friday", "next saturday", "next sunday",
]
CLOCK_TIME_RE = re.compile(r"\b(\d{1,2}(:\d{2})?\s?(am|pm))\b|\b([01]?\d|2[0-3]):[0-5]\d\b", re.IGNORECASE)
MONTHS = "January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec"
EXPLICIT_DATE_RE = re.compile(
    rf"\b(({MONTHS})\s+\d{{1,2}}(st|nd|rd|th)?(,?\s+\d{{4}})?|\d{{1,2}}\s+({MONTHS})(,?\s+\d{{4}})?|\d{{4}}-\d{{2}}-\d{{2}}|\d{{1,2}}/\d{{1,2}}(/\d{{2,4}})?)\b",
    re.IGNORECASE,
)


def normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text.lower()).strip()


def contains_verbatim(candidate: str | None, source: str) -> bool:
    if not candidate or not candidate.strip():
        return False
    return normalize(candidate) in normalize(source)


def extract_temporal_phrases(text: str) -> list[str]:
    found: list[str] = []
    lower = text.lower()
    for phrase in KEYWORD_PHRASES:
        if re.search(rf"\b{re.escape(phrase)}\b", lower):
            found.append(phrase)
    for regex in (CLOCK_TIME_RE, EXPLICIT_DATE_RE):
        for m in regex.finditer(text):
            found.append(m.group(0))
    return found


def is_deadline_grounded(phrase: str | None, source: str) -> bool:
    if not phrase:
        return False
    evidence = extract_temporal_phrases(source)
    if not evidence:
        return False
    return contains_verbatim(phrase, source)


RESOURCE_HOST_MAP = [
    ("figma.com", "figma"),
    ("github.com", "github"),
    ("docs.google.com", "googleDocs"),
    ("drive.google.com", "googleDrive"),
    ("atlassian.net", "jira"),
    ("jira.com", "jira"),
    ("notion.so", "notion"),
    ("notion.site", "notion"),
]


def resource_type_for_url(url: str) -> str:
    host = url.split("/")[2].lower() if "://" in url else ""
    for needle, kind in RESOURCE_HOST_MAP:
        if needle in host:
            return kind
    return "genericURL"


def extract_resources(text: str) -> list[dict[str, str]]:
    seen: set[str] = set()
    resources = []
    for m in URL_RE.finditer(text):
        url = m.group(0).rstrip(".,;:!?\"'")
        if url.endswith(")") and url.count("(") < url.count(")"):
            url = url[:-1]
        if url in seen:
            continue
        seen.add(url)
        resources.append({"url": url, "type": resource_type_for_url(url)})
    return resources


@dataclass
class GroundingResult:
    understanding: dict[str, Any]
    resources: list[dict[str, str]]
    rejections: list[dict[str, str]] = field(default_factory=list)


def ground(understanding: dict[str, Any], source: str) -> GroundingResult:
    u = dict(understanding)
    rejections: list[dict[str, str]] = []

    deadline = (u.get("deadlineText") or "").strip() or None
    if deadline:
        if is_deadline_grounded(deadline, source):
            u["deadlineText"] = deadline
        else:
            rejections.append({"field": "deadlineText", "value": deadline, "reason": "not present in source"})
            u["deadlineText"] = None

    for field_name in ("trigger", "waitingFor", "target"):
        value = (u.get(field_name) or "").strip() or None
        if value and contains_verbatim(value, source):
            u[field_name] = value
        else:
            if value:
                rejections.append({"field": field_name, "value": value, "reason": "not present in source"})
            u[field_name] = None

    extracted = extract_resources(source)
    extracted_urls = {r["url"] for r in extracted}
    labels = {sug["url"]: sug["label"] for sug in (u.get("resourceLabels") or []) if sug.get("url") in extracted_urls}
    for sug in u.get("resourceLabels") or []:
        if sug.get("url") not in extracted_urls:
            rejections.append({"field": "resourceLabels", "value": sug.get("url", ""), "reason": "URL not found in source"})
    resources = [{"url": r["url"], "type": r["type"], "label": labels.get(r["url"])} for r in extracted]

    return GroundingResult(understanding=u, resources=resources, rejections=rejections)


def classify(u: dict[str, Any]) -> str | None:
    if not u.get("hasTrackableIntent"):
        return None
    if u.get("polarity") == "negative":
        return None
    if u.get("temporalState") == "past":
        return None
    speech_act = u.get("speechAct")
    if speech_act == "reminder":
        return "remember"
    if speech_act == "commitment":
        if u.get("owner") == "self" or u.get("actor") == "self":
            return "action"
        if u.get("owner") == "other" or u.get("actor") == "other":
            if u.get("waitingFor") or u.get("responseExpected") is True:
                return "waiting"
            return None
        return None
    if speech_act in ("request", "instruction"):
        direction = u.get("direction")
        if direction == "incoming":
            return "action"
        if direction == "outgoing":
            return "waiting" if u.get("waitingFor") else "request"
        if u.get("owner") == "self":
            return "action"
        return "waiting" if u.get("waitingFor") else "request"
    # statement / question / unknown / missing
    if u.get("waitingFor") or (u.get("commitmentStrength") == "committed" and u.get("owner") == "other"):
        return "waiting"
    return None


def matches_expected(predicted: str | None, expected: str) -> bool:
    predicted_label = predicted or "no_intent"
    if "_or_" in expected:
        return predicted_label in expected.split("_or_")
    return predicted_label == expected


def load_api_key(cli_key: str | None) -> str:
    if cli_key:
        return cli_key
    env_key = os.environ.get("GEMINI_API_KEY")
    if env_key:
        return env_key
    if SECRETS_PATH.exists():
        try:
            data = json.loads(SECRETS_PATH.read_text())
            key = data.get(GEMINI_API_KEY_ACCOUNT)
            if key:
                return key
        except (json.JSONDecodeError, OSError):
            pass
    print(
        "No Gemini API key found. Set GEMINI_API_KEY, pass --api-key, or configure one via "
        "Preferences -> IntentOS -> Gemini API Key (stored in ~/.openclip/secrets.json).",
        file=sys.stderr,
    )
    sys.exit(1)


def call_gemini(source_text: str, api_key: str, model: str, timeout: float = 20.0) -> tuple[dict[str, Any], float, str]:
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    body = json.dumps({
        "systemInstruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        "contents": [{"parts": [{"text": source_text}]}],
        "generationConfig": {
            "responseMimeType": "application/json",
            "responseSchema": UNDERSTANDING_SCHEMA,
            "temperature": 0.1,
        },
    }).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        headers={"x-goog-api-key": api_key, "Content-Type": "application/json"},
        method="POST",
    )
    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"HTTP {exc.code}: {exc.read().decode('utf-8', errors='replace')[:300]}") from exc
    latency_ms = (time.monotonic() - started) * 1000
    text = payload["candidates"][0]["content"]["parts"][0]["text"]
    return json.loads(text), latency_ms, text


def median(values: list[float]) -> float | None:
    return statistics.median(values) if values else None


def p95(values: list[float]) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = min(len(ordered) - 1, int(round(0.95 * (len(ordered) - 1))))
    return ordered[index]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--api-key", default=None, help="Overrides GEMINI_API_KEY / secrets.json. Never commit this.")
    parser.add_argument("--limit", type=int, default=None, help="Only run the first N cases (for a quick smoke run).")
    args = parser.parse_args()

    api_key = load_api_key(args.api_key)
    cases = [json.loads(line) for line in DATASET_PATH.read_text().splitlines() if line.strip()]
    if args.limit:
        cases = cases[: args.limit]

    results = []
    latencies: list[float] = []
    for case in cases:
        source = case["source"]
        try:
            raw_understanding, latency_ms, raw_text = call_gemini(source, api_key, args.model)
            latencies.append(latency_ms)
        except Exception as exc:  # noqa: BLE001 - report and continue the eval run
            results.append({**case, "error": str(exc)})
            print(f"[{case['id']}] ERROR: {exc}", file=sys.stderr)
            continue

        grounding = ground(raw_understanding, source)
        predicted_type = classify(grounding.understanding)
        match = matches_expected(predicted_type, case["expected_type"])

        hallucinated_deadline = bool(raw_understanding.get("deadlineText")) and grounding.understanding.get("deadlineText") is None
        hallucinated_person = any(
            r["field"] in ("target", "waitingFor") for r in grounding.rejections
        )
        hallucinated_resource = any(r["field"] == "resourceLabels" for r in grounding.rejections)

        results.append({
            "id": case["id"],
            "category": case["category"],
            "source": source,
            "expected_type": case["expected_type"],
            "predicted_type": predicted_type or "no_intent",
            "match": match,
            "predicted_deadline_text": grounding.understanding.get("deadlineText"),
            "expected_deadline_text": case.get("expected_deadline_text"),
            "predicted_resources": grounding.resources,
            "expected_resource_type": case.get("expected_resource_type"),
            "grounding_rejections": grounding.rejections,
            "hallucinated_deadline": hallucinated_deadline,
            "hallucinated_person": hallucinated_person,
            "hallucinated_resource": hallucinated_resource,
            "latency_ms": latency_ms,
            "raw_response": raw_text,
        })

    with RESULTS_PATH.open("w") as f:
        for r in results:
            f.write(json.dumps(r) + "\n")

    scored = [r for r in results if "error" not in r]
    total = len(scored)
    accuracy = sum(1 for r in scored if r["match"]) / total if total else 0.0

    def precision_recall(label: str) -> tuple[float | None, float | None]:
        predicted_positive = [r for r in scored if r["predicted_type"] == label]
        actual_positive = [r for r in scored if r["expected_type"] == label or (f"_or_{label}" in r["expected_type"]) or (f"{label}_or_" in r["expected_type"])]
        true_positive = [r for r in predicted_positive if r["match"]]
        precision = len(true_positive) / len(predicted_positive) if predicted_positive else None
        recall = len(true_positive) / len(actual_positive) if actual_positive else None
        return precision, recall

    action_p, action_r = precision_recall("action")
    waiting_p, waiting_r = precision_recall("waiting")
    no_intent_p, no_intent_r = precision_recall("no_intent")

    false_positive_obligations = sum(
        1 for r in scored
        if r["expected_type"] in ("no_intent",) and r["predicted_type"] != "no_intent"
    )
    false_positive_rate = false_positive_obligations / total if total else 0.0

    hallucinated_deadline_rate = sum(1 for r in scored if r["hallucinated_deadline"]) / total if total else 0.0
    hallucinated_person_rate = sum(1 for r in scored if r["hallucinated_person"]) / total if total else 0.0
    hallucinated_resource_rate = sum(1 for r in scored if r["hallucinated_resource"]) / total if total else 0.0

    resource_cases = [r for r in scored if r["expected_resource_type"]]
    resource_correct = sum(
        1 for r in resource_cases
        if any(res["type"] == r["expected_resource_type"] for res in r["predicted_resources"])
    )
    resource_accuracy = resource_correct / len(resource_cases) if resource_cases else None

    summary = {
        "model": args.model,
        "total_cases": total,
        "errors": len(results) - total,
        "classification_accuracy": accuracy,
        "action_precision": action_p,
        "action_recall": action_r,
        "waiting_precision": waiting_p,
        "waiting_recall": waiting_r,
        "no_intent_precision": no_intent_p,
        "no_intent_recall": no_intent_r,
        "false_positive_obligation_rate": false_positive_rate,
        "hallucinated_deadline_rate": hallucinated_deadline_rate,
        "hallucinated_person_rate": hallucinated_person_rate,
        "hallucinated_resource_rate": hallucinated_resource_rate,
        "resource_extraction_accuracy": resource_accuracy,
        "median_latency_ms": median(latencies),
        "p95_latency_ms": p95(latencies),
    }

    print(json.dumps(summary, indent=2))
    print(f"\nWrote {len(results)} results to {RESULTS_PATH}")
    print(f"Update {DOCS_PATH} by hand with this summary (never auto-commit fabricated numbers).")


if __name__ == "__main__":
    main()
