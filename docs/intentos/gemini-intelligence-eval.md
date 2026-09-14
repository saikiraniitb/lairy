# Gemini Intent Intelligence — Evaluation

Evaluation harness for the Intent Intelligence V1 (Gemini) milestone. Lives in
[`tools/intent-intelligence-eval/`](../../tools/intent-intelligence-eval/).

## What this measures

`run_eval.py` sends every case in [`dataset.jsonl`](../../tools/intent-intelligence-eval/dataset.jsonl)
(95 hand-authored examples) through the real Gemini structured-output endpoint, using the exact
same system prompt and JSON Schema as
[`GeminiIntentParser.swift`](../../Sources/OpenClip/Intent/GeminiIntentParser.swift) (the two are
kept in sync by hand — see the `KEEP IN SYNC` markers in both files). It then re-implements the
same deterministic grounding (`IntentGroundingValidator.swift`) and classification
(`IntentClassifier.swift`) logic in Python, so the eval measures the whole pipeline IntentOS
actually runs, not just the raw model call.

The dataset covers: self-owned ACTION, incoming-request ACTION, outgoing REQUEST, WAITING,
REMEMBER, NO_INTENT (past tense, negation, purely informational), third-party commitments,
conditional/trigger-gated language, ambiguous suggestions, resource/URL extraction, time-only
mentions, and adversarial no-deadline / no-person cases designed specifically to catch
hallucination.

## Metrics reported

- Classification accuracy (overall, and per intent type where the dataset marks an unambiguous
  expected type — some third-party/conditional/ambiguous cases intentionally accept more than one
  correct answer, matching the milestone's own examples)
- ACTION / WAITING / NO_INTENT precision and recall
- False-positive obligation rate (a NO_INTENT case that got tracked as something) — the single
  metric this milestone cares about most
- Hallucinated-deadline rate, hallucinated-person rate, hallucinated-resource rate (all three
  should be at or near zero — grounding is supposed to catch every one of these deterministically,
  so a non-zero rate here means either the grounding validator has a gap or Gemini is proposing
  something the grounding logic can't recognize as ungrounded)
- Resource extraction accuracy (against the dataset's `expected_resource_type`)
- Median and p95 Gemini latency

## How to run it

```bash
export GEMINI_API_KEY=...   # or configure one via Preferences -> IntentOS -> Gemini API Key first
python3 tools/intent-intelligence-eval/run_eval.py
```

This writes one JSON line per case to `tools/intent-intelligence-eval/results.jsonl` (git-ignored —
it can contain real captured phrasing from the dataset and raw model output) and prints a summary.
Update the table below **by hand** from that printed summary after a real run. Never invent numbers
here — an unmeasured metric is written as "not yet measured," not as a plausible-looking guess.

## Latest results

**Status: not yet measured.** This milestone's implementation (Gemini parser, grounding validator,
classifier, resource extraction) is complete and covered by unit tests
(`GeminiIntentParserTests`, `IntentGroundingValidatorTests`, `IntentClassifierTests`,
`IntentResourceExtractorTests`, `TemporalPhraseExtractorTests`), but no Gemini API key was
available in the environment this milestone was built in, so the harness above has not yet been
run against the live API. Add a key via Preferences → IntentOS → Gemini API Key (or `GEMINI_API_KEY`)
and run `run_eval.py`, then replace this table:

| Metric | Value |
| --- | --- |
| Model | not yet measured |
| Classification accuracy | not yet measured |
| ACTION precision / recall | not yet measured |
| WAITING precision / recall | not yet measured |
| NO_INTENT precision / recall | not yet measured |
| False-positive obligation rate | not yet measured |
| Hallucinated deadline rate | not yet measured |
| Hallucinated person rate | not yet measured |
| Hallucinated resource rate | not yet measured |
| Resource extraction accuracy | not yet measured |
| Median latency | not yet measured |
| P95 latency | not yet measured |

## What has been verified without a live key

The parts of the pipeline that don't require a network call are covered by deterministic unit
tests and pass today:

- `IntentClassifierTests` — the milestone's required test cases A–J (deterministic, given a
  simulated understanding matching each sentence's intended semantic parse).
- `IntentGroundingValidatorTests` — the exact Google Chat hallucinated-deadline regression case,
  a hallucinated-person rejection, resource URLs never trusted from the provider, and grounded
  values surviving.
- `IntentResourceExtractorTests` / `TemporalPhraseExtractorTests` — deterministic URL and temporal
  phrase extraction.
- `GeminiIntentParserTests` — the full parser round-trip (decode → ground → classify → draft)
  against fixture Gemini responses for both named regression cases (Google Chat Figma review,
  WhatsApp session request), plus error paths (missing key, HTTP failure, unreadable response,
  empty selection short-circuiting before any network call).

These confirm the grounding/classification *logic* is correct; they cannot confirm Gemini's actual
extraction quality on real-world phrasing, which is exactly what `run_eval.py` measures once a key
is available.
