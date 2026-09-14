# OPENCLIP REUSE ASSESSMENT

Assessment basis: OpenClip `dcb47ac` (`main`, inspected 2026-09-14).

## Reusable

- **Selection capture:** `MacSelectionMonitor`, `SelectionRetrievalCoordinator`, and the
  `OpenSelection` dependency already retrieve explicitly selected text using Accessibility and
  retain the source application's name and bundle identifier in `SelectionContext`.
- **Invocation shell:** the floating `NSPanel`, popup positioning, keyboard navigation, action
  search, loading feedback, Escape handling, and result-card presentation are suitable foundations
  for Capture Intent and its compact preview.
- **Action architecture:** `Action`, `ActionContext`, `ActionRegistry`, and `ActionCoordinator`
  already provide a first-class built-in action path without routing through extensions.
- **Async execution:** actions already perform asynchronously and the popup controller already
  supports cancellable loading state, so local inference need not block the main thread.
- **Provider infrastructure:** OpenClip's existing cloud provider and secret storage can support an
  explicitly invoked fallback later. It must not be used as the primary IntentOS parser.
- **Settings:** `SettingsStore` and typed `SettingKey` values are appropriate for a developer-mode
  confidence threshold and the cloud-fallback-disabled-by-default flag.
- **Diagnostics:** `Log`, the in-memory debug buffer, and rotating local log sink can carry
  privacy-safe parser events and timings.
- **App lifecycle/signing:** the menu-bar application lifecycle, Accessibility onboarding,
  ad-hoc development signing, hardened runtime, and packaging scripts can be retained.
- **Testing:** the pure Core target, strict Swift concurrency, dependency injection patterns, and
  headless XCTest setup provide good seams for domain, repository, parser, and UI state tests.

## Needs modification

- OpenClip currently presents generic actions and generic text result cards. IntentOS needs a
  dedicated structured preview state with Track, Edit, Ignore, and uncertainty controls.
- OpenClip may use clipboard fallback for selection-free shortcuts. Capture Intent must reject that
  path: its privacy boundary is a live, explicit text selection only.
- `ActionCoordinator` must register a native Capture Intent action composed with an
  `IntentParsing` implementation, not a script extension or a generic AI preset.
- The menu-bar surface needs an Intent Inbox entry and a small native inbox window.
- Settings need IntentOS-specific local-inference confidence and explicit cloud-fallback controls.
- Debugging must show parser artifacts only on an explicit developer surface; routine local metrics
  must never contain source text.
- Product naming, bundle metadata, update behavior, and visual identity need an IntentOS pass before
  distribution. During prototype development, upstream identifiers are deliberately changed only
  where required to avoid destabilizing the interaction shell.

## New IntentOS components

- Pure Core domain types: `IntentType`, `IntentStatus`, `IntentDraft`, `CapturedIntent`, parser
  diagnostics, and conservative date resolution.
- Provider-neutral `IntentParsing` protocol and parse result (`intent`, `noIntent`, `uncertain`).
- Local `IntentRepository` with atomic Codable-file persistence in Application Support.
- `NeedleIntentParser`, backed by one persistent helper process and newline-delimited JSON IPC for
  the prototype.
- Intent capture/preview coordinator and structured SwiftUI preview.
- Intent Inbox store, window, and item detail/source inspection.
- Privacy-safe local product metrics plus an opt-in debug record store.
- Needle feasibility harness, fixed benchmark corpus, JSONL results, and generated summary.

## Potential conflicts

- **Automatic popup versus explicit capture:** OpenClip can appear immediately after selection.
  IntentOS may reuse that shell, but parsing starts only when Capture Intent is invoked.
- **Clipboard fallback:** OpenClip intentionally supports it; IntentOS Capture Intent must not.
- **Generic action result semantics:** saving an intent is a state mutation requiring explicit
  confirmation, so it cannot be represented as an automatically delivered `.text` result.
- **Modal selection suppression:** the existing popup suppresses same-app rereads while a result card
  is open. The structured preview should preserve that behavior.
- **Hardened runtime:** loading an unsigned third-party native library directly may require library
  validation entitlements OpenClip intentionally does not grant. A separate bundled executable or
  helper is safer than in-process `dlopen` for V0.
- **App sandbox:** OpenClip is currently not App-Sandboxed. Its hardened-runtime entitlement set is
  intentionally minimal; spawning a bundled helper does not itself require adding an entitlement.
- **Updates:** the upstream Sparkle feed must not update an IntentOS fork to an OpenClip release.
  It must be disabled or replaced before distribution.
- **Eight-gigabyte target:** model installation, warm helper lifetime, and diagnostics must remain
  bounded. No Python training stack belongs in the shipped app.

## Licensing considerations

- OpenClip is MIT licensed. Preserve its `LICENSE`, copyright notice, repository history, and clear
  attribution in the README and About surface.
- The current Needle repository declares Apache-2.0 in `pyproject.toml` and includes the Apache 2.0
  license. If its engine/object code is distributed, include a copy of that license, preserve any
  notices shipped with the artifact, mark locally modified source files, and verify whether the
  downloaded engine/model artifact has additional terms before bundling.
- The spike may download Needle into an ignored local environment/cache. No model, runtime binary,
  wheel, cache, or generated credential is committed by default.
- A legal/technical packaging decision is deferred until the exact standalone macOS artifact is
  inspected. Development download support is not the same as permission or readiness to redistribute.

## Recommended architecture

```text
Selected text + source app metadata
              |
       Capture Intent action
              |
       IntentCaptureCoordinator
              |
        IntentParsing protocol
              |
   NeedleIntentParser (default/local)
              |
      confidence + diagnostics
       /                    \
normal preview          uncertain preview
       |                    | optional user click
      Track                 CloudIntentParser
       |                    |
       +------ preview -----+
              |
       IntentRepository
              |
         Intent Inbox
```

Keep intent schema, state, persistence, validation, metrics, and UX in IntentOS. Needle is a
replaceable adapter. For V0, prefer a warm persistent helper using JSON Lines over stdin/stdout:
there is no localhost listener, the Swift app owns process lifetime, and the interface is easy to
replace with the official standalone runner or a native binding after validation.
