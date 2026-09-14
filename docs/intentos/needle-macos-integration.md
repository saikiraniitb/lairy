# NEEDLE MACOS INTEGRATION

## Chosen method

For the source-run V0 prototype, Swift owns one persistent local helper process and exchanges one
JSON object per line over stdin/stdout. The helper runs the official `cactus-needle==2.0.12` Python
package with the official Needle 2 ARM64 engine, sets `NEEDLE_TELEMETRY=0` and `DO_NOT_TRACK=1`
before import, initializes one toolset, and calls `reset()` between selections.

This is a development bridge, not a decision to ship Python inside the application. The Swift
surface is `IntentParsing`; no domain, persistence, or UI code imports Needle concepts.

## Why

- It is the smallest reliable way to exercise the exact package used by the feasibility benchmark.
- It keeps the model warm and avoids launching Python/model state for every selected sentence.
- Pipes expose no unauthenticated localhost service.
- The helper and model runtime live under an ignored spike directory, so heavyweight/generated
  artifacts are not committed.
- The benchmark verdict is currently FAIL. Bundling an opaque 14 MB engine before the parsing
  approach is viable would add release/signing work without product value.

## Alternatives considered

1. **Official standalone ARM64 runner:** inspected and functional. It supports one-shot JSON and a
   persistent HTTP server (`POST /complete`, `POST /reset`) but has no documented pipe server mode.
   A loopback listener is unnecessary exposure for V0.
2. **Official static C library:** the downloaded package includes `libneedle.a` and a stable-looking
   four-function header (`needle_init`, `needle_complete`, `needle_reset`, `needle_load`). Static
   linking avoids dynamic-library-validation entitlements and is the leading packaging candidate
   after the model/schema is good enough.
3. **Dynamic native library:** technically callable through the same C surface, but in-process
   `dlopen` conflicts with OpenClip's intentionally strict hardened-runtime/library-validation
   posture unless signed and embedded carefully.
4. **WebAssembly component:** portable and signed upstream, but adding a wasm component host is
   more machinery than the prototype needs.

## Cold start

Measured model initialization on this M2 baseline: approximately **1.5 seconds** on the final run
(an earlier uncached/process-state run measured approximately 2.1 seconds). The helper emits a
`ready` handshake only after initialization.

## Warm latency

75-case final corpus: **194.1 ms median**, **261.2 ms p95** on the latest verification run.

## RAM

**57.1 MB peak** observed/reported on the latest verification run (earlier runs reached 64.1 MB).
This includes Python and the helper,
not only the engine's advertised model-session footprint.

## Packaging implications

- Current developer builds require `tools/needle-spike/.venv` and the ignored engine download.
- The source path is discovered from `#filePath`; `INTENTOS_NEEDLE_PYTHON` and
  `INTENTOS_NEEDLE_HELPER` override it for relocated development builds.
- A distributable build must not rely on the source checkout or a user Python installation.
- Before distribution, either statically link the official library or bundle/re-sign the official
  executable, copy the Apache-2.0 license and any upstream notices, verify model artifact terms,
  and add the binary to the inside-out signing verification flow.
- No Needle runtime/model binary is committed in V0.
