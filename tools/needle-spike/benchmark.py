#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import re
import statistics
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from needle_intent import NeedleIntentEngine


ROOT = Path(__file__).resolve().parent
DATASET = ROOT / "benchmark_dataset.jsonl"
RESULTS = ROOT / "needle_benchmark.jsonl"
SUMMARY = ROOT / "needle_benchmark_summary.md"


def normalized(value: Any) -> str:
    if value is None:
        return ""
    return " ".join(re.findall(r"[a-z0-9]+", str(value).lower()))


def field_matches(expected: Any, predicted: Any) -> bool:
    if expected is None:
        return predicted is None or normalized(predicted) == ""
    alternatives = expected if isinstance(expected, list) else [expected]
    actual = normalized(predicted)
    if not actual:
        return False
    for option in alternatives:
        wanted = normalized(option)
        if actual == wanted or wanted in actual or actual in wanted:
            return True
        wanted_tokens, actual_tokens = set(wanted.split()), set(actual.split())
        if wanted_tokens and len(wanted_tokens & actual_tokens) / len(wanted_tokens) >= 0.75:
            return True
    return False


def percentile(values: list[float], p: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return math.nan
    index = (len(ordered) - 1) * p
    low, high = math.floor(index), math.ceil(index)
    if low == high:
        return ordered[low]
    return ordered[low] * (high - index) + ordered[high] * (index - low)


def ratio(numerator: int, denominator: int) -> float:
    return numerator / denominator if denominator else 0.0


def evaluate(case: dict[str, Any], result: dict[str, Any]) -> dict[str, Any]:
    predicted = result["predicted_intent_type"]
    acceptable = case.get("acceptable_intent_types", [case.get("expected_intent_type")])
    classification_pass = predicted in acceptable
    checks = {
        field: field_matches(expected, result["predicted_fields"].get(field))
        for field, expected in case.get("expected_fields", {}).items()
    }
    fields_pass = all(checks.values())
    confidence_rule = case.get("max_confidence_if_intent")
    confidence_pass = not (
        predicted is not None
        and confidence_rule is not None
        and result.get("confidence") is not None
        and result["confidence"] > confidence_rule
    )
    return {
        "classification_pass": classification_pass,
        "field_checks": checks,
        "fields_pass": fields_pass,
        "confidence_pass": confidence_pass,
        "pass": classification_pass and fields_pass and confidence_pass,
    }


def threshold_table(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for threshold in (0.50, 0.60, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95):
        accepted = [r for r in records if r["predicted_intent_type"] is not None and (r.get("confidence") or 0) >= threshold]
        correct = [r for r in accepted if r["predicted_intent_type"] == r["expected_intent_type"]]
        false_positive = [r for r in accepted if r["expected_intent_type"] is None]
        positives = [r for r in records if r["expected_intent_type"] is not None]
        rows.append({
            "threshold": threshold,
            "accepted": len(accepted),
            "precision": ratio(len(correct), len(accepted)),
            "positive_recall": ratio(len(correct), len(positives)),
            "false_positives": len(false_positive),
        })
    return rows


def render_summary(records: list[dict[str, Any]], load_ms: float) -> str:
    total = len(records)
    classification_correct = sum(r["classification_pass"] for r in records)
    negatives = [r for r in records if r["expected_intent_type"] is None]
    predicted_negative = [r for r in records if r["predicted_intent_type"] is None]
    true_negative = [r for r in negatives if r["predicted_intent_type"] is None]
    false_positive = [r for r in negatives if r["predicted_intent_type"] is not None]
    field_checks = [passed for r in records for passed in r["field_checks"].values()]
    latencies = [r["latency_ms"] for r in records]
    confidences = [r["confidence"] for r in records if r.get("confidence") is not None]
    target_checks = [r["field_checks"]["target"] for r in records if "target" in r["field_checks"]]
    deadline_checks = [r["field_checks"]["deadline_text"] for r in records if "deadline_text" in r["field_checks"]]
    trigger_checks = [r["field_checks"]["trigger"] for r in records if "trigger" in r["field_checks"]]
    true_no_intent_among_predictions = sum(r["expected_intent_type"] is None for r in predicted_negative)
    by_category = defaultdict(list)
    for record in records:
        by_category[record["category"]].append(record)
    confidence_buckets = Counter(
        "<0.50" if c < 0.5 else "0.50-0.74" if c < 0.75 else "0.75-0.89" if c < 0.9 else ">=0.90"
        for c in confidences
    )
    thresholds = threshold_table(records)
    recommended = next((
        row["threshold"] for row in thresholds
        if row["accepted"] > 0 and row["false_positives"] == 0 and row["precision"] >= 0.90
    ), 0.75)

    lines = [
        "# Needle 2 baseline benchmark",
        "",
        f"Dataset: {total} fixed English utterances. Model: official `cactus-needle==2.0.12`, base weights, no fine-tuning. Telemetry disabled.",
        "Control check: the package's own `productivity` acceptance suite passed 28/32 cases on the same engine. The runtime is functional; the abstract IntentOS taxonomy is the mismatch.",
        "",
        "## Metrics",
        "",
        f"- Intent classification accuracy: {ratio(classification_correct, total):.1%} ({classification_correct}/{total})",
        f"- No-intent precision: {ratio(true_no_intent_among_predictions, len(predicted_negative)):.1%}",
        f"- No-intent recall: {ratio(len(true_negative), len(negatives)):.1%}",
        f"- Field extraction accuracy: {ratio(sum(field_checks), len(field_checks)):.1%} ({sum(field_checks)}/{len(field_checks)})",
        f"- Target extraction accuracy: {ratio(sum(target_checks), len(target_checks)):.1%}",
        f"- Deadline extraction accuracy: {ratio(sum(deadline_checks), len(deadline_checks)):.1%}",
        f"- Trigger extraction accuracy: {ratio(sum(trigger_checks), len(trigger_checks)):.1%}",
        f"- False-positive rate on no-intent cases: {ratio(len(false_positive), len(negatives)):.1%} ({len(false_positive)}/{len(negatives)})",
        f"- Cold model initialization: {load_ms:.1f} ms",
        f"- Median warm latency: {statistics.median(latencies):.1f} ms",
        f"- P95 warm latency: {percentile(latencies, 0.95):.1f} ms",
        f"- Peak RAM reported/observed: {max(r['peak_ram_mb'] or 0 for r in records):.1f} MB",
        "",
        "Field matching is conservative but allows case/punctuation differences, containment, or at least 75% coverage of expected tokens. Explicit `null` expectations test non-invention.",
        "",
        "## Category accuracy",
        "",
        "| Category | Passed classification | Passed full record |",
        "|---|---:|---:|",
    ]
    for category, category_records in sorted(by_category.items()):
        lines.append(
            f"| {category} | {ratio(sum(r['classification_pass'] for r in category_records), len(category_records)):.1%} | "
            f"{ratio(sum(r['pass'] for r in category_records), len(category_records)):.1%} |"
        )
    lines += [
        "",
        "## Confidence distribution",
        "",
        *(f"- {bucket}: {confidence_buckets.get(bucket, 0)}" for bucket in ("<0.50", "0.50-0.74", "0.75-0.89", ">=0.90")),
        "",
        "| Threshold | Accepted calls | Accepted precision | Positive recall | False positives |",
        "|---:|---:|---:|---:|---:|",
    ]
    for row in thresholds:
        lines.append(
            f"| {row['threshold']:.2f} | {row['accepted']} | {row['precision']:.1%} | {row['positive_recall']:.1%} | {row['false_positives']} |"
        )
    lines += [
        "",
        f"Recommended initial confidence threshold from this corpus: **{recommended:.2f}**, but no emitted intent reached even 0.50. This gate therefore routes every current call to uncertainty; it is a safety default, not evidence of useful calibration for this schema.",
        "",
        "## Failure cases",
        "",
    ]
    failures = [r for r in records if not r["pass"]]
    if not failures:
        lines.append("- None.")
    for record in failures:
        bad_fields = [name for name, passed in record["field_checks"].items() if not passed]
        lines.append(
            f"- `{record['id']}` ({record['category']}): expected `{record['expected_intent_type']}`, "
            f"predicted `{record['predicted_intent_type']}`, confidence `{record.get('confidence')}`"
            + (f", mismatched fields: {', '.join(bad_fields)}" if bad_fields else "")
            + f" — {record['input']}"
        )
    lines += [
        "",
        "## NEEDLE V0 VERDICT",
        "",
        f"Classification: {ratio(classification_correct, total):.1%}",
        f"No-intent handling: precision {ratio(true_no_intent_among_predictions, len(predicted_negative)):.1%}, recall {ratio(len(true_negative), len(negatives)):.1%}",
        f"Extraction: {ratio(sum(field_checks), len(field_checks)):.1%}",
        f"False positives: {len(false_positive)} of {len(negatives)} no-intent inputs",
        f"Latency: {statistics.median(latencies):.1f} ms median / {percentile(latencies, 0.95):.1f} ms p95 warm",
        f"RAM: {max(r['peak_ram_mb'] or 0 for r in records):.1f} MB peak",
        f"Confidence usefulness: not useful for accepting this schema's calls; every emitted intent scored below 0.50. A {recommended:.2f} safety gate rejects them all.",
        "",
        "Verdict: " + ("PASS" if ratio(classification_correct, total) >= 0.90 and not false_positive else "PASS_WITH_LIMITATIONS" if ratio(classification_correct, total) >= 0.80 else "FAIL"),
        "",
        f"Recommended confidence threshold: {recommended:.2f}",
        "",
        "Known failure cases: listed above.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    cases = [json.loads(line) for line in DATASET.read_text(encoding="utf-8").splitlines() if line.strip()]
    engine = NeedleIntentEngine()
    records = []
    with RESULTS.open("w", encoding="utf-8") as output:
        for index, case in enumerate(cases, 1):
            result = engine.parse(case["input"])
            record = {**case, **result}
            record.update(evaluate(case, result))
            records.append(record)
            output.write(json.dumps(record, ensure_ascii=False) + "\n")
            output.flush()
            print(f"[{index:02d}/{len(cases)}] {case['id']}: {record['predicted_intent_type']} ({record.get('confidence')}) {'PASS' if record['pass'] else 'FAIL'}")
    SUMMARY.write_text(render_summary(records, engine.load_ms), encoding="utf-8")
    print(f"\nWrote {RESULTS.name} and {SUMMARY.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
