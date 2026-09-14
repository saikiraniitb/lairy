# NEEDLE RUNTIME RESEARCH

Research basis: official `cactus-compute/needle` repository commit
`956840ff176bfe179bb2f230b726f4be44fb11cf` (2026-09-12), inspected 2026-09-14.

## Official baseline

- Package: `cactus-needle` (Python 3.9+), version `2.0.12` at the inspected commit.
- Base model: Needle 2, a 45M-parameter, approximately 14 MB engine with grammar-constrained tool
  calls and an advertised approximately 28 MB full-session footprint.
- Python API: `needle.Needle(tools=..., system=...)` and `agent.complete(...)` return structured
  function calls, confidence, throughput, validation, and peak-RAM fields.
- Unsupported/off-topic input is represented by an empty function-call list.
- Official telemetry opt-out: `NEEDLE_TELEMETRY=0` (also `DO_NOT_TRACK=1`). The spike and helper set
  both before importing Needle.
- The engine is fetched once, cached, and inference is local thereafter.

## Confidence and fine-tuning

The base model's confidence is the minimum of a calibrated post-hoc head and call-token decoding
probability. Official documentation explicitly states that calibration does **not** carry over to
fine-tuned weights: tuned agents report `confidence = None`. IntentOS therefore benchmarks the base
model and does not fine-tune in V0.

## Deployment surfaces found

1. Python package with a native generation-specific engine loaded behind its API.
2. Official `needle download macos-arm64 --generation 2` standalone artifact.
3. Official WebAssembly component and WIT contract.
4. Native generation-specific library override via `NEEDLE2_LIB_PATH`.

The standalone artifact's machine-readable contract and redistributable contents still require
inspection after download. Until validated, the reliable prototype integration is a persistent,
telemetry-disabled Python helper with JSON Lines over pipes. It initializes one agent and resets its
conversation between independent selections; Swift never launches one interpreter per inference.

## Primary sources

- <https://github.com/cactus-compute/needle>
- <https://github.com/cactus-compute/needle/blob/main/doc/apis.md>
- <https://github.com/cactus-compute/needle/blob/main/doc/finetuning.md>
- <https://github.com/cactus-compute/needle/blob/main/LICENSE>

