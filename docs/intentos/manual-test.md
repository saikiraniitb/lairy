# IntentOS V1 manual test

## Prerequisites

IntentOS owns the intelligence layer — there is no Preferences UI to pick a provider, a model, or
enter an API key. Intent Intelligence is Gemini by default, configured entirely through the
environment:

1. Install full Xcode 16 or newer and select it in Xcode settings or with `xcode-select`.
2. Get a Gemini API key and set it in your shell, then run the dev script from that same shell:
   ```bash
   export GEMINI_API_KEY="..."
   ./scripts/dev_run.sh
   ```
   The script never stores or hardcodes this value — it only checks whether it's set and reports
   that (without printing it) before launching. Running `./scripts/dev_run.sh` in a shell where
   `GEMINI_API_KEY` was never exported launches IntentOS with Intent Intelligence disabled (see
   the "not configured" case below).
3. **From Xcode instead:** Product menu → Scheme → Edit Scheme… → **Run** → **Arguments** tab →
   **Environment Variables** → add `GEMINI_API_KEY` with your key. Never commit a real value here —
   scheme edits with a real key belong in your local, uncommitted scheme state only.
4. Grant the built app Accessibility permission in **System Settings → Privacy & Security → Accessibility**.
5. (Developer/research path only — never exposed to normal users) To exercise Needle instead of
   Gemini, set `INTENTOS_INTELLIGENCE_PROVIDER=needle` alongside the above (DEBUG builds only).
   From `tools/needle-spike`, create `.venv`, install `requirements.txt`, and fetch generation 2 as
   shown in that directory's README. Keep **Needle confidence threshold** at 0.75 in Preferences →
   General → IntentOS Developer — the measured base model will normally show these cases as
   uncertain; use **Edit Manually** to correct them.

## Known V1 limitation: Apple Notes

Apple Notes' live-selection retrieval is currently unsupported/unreliable and is **not** a release
blocker for this milestone (see the selection-retrieval investigation elsewhere in this repo's
history). Do not test Notes as part of this milestone's sign-off — use Google Chat, WhatsApp Web,
Safari/Chrome, or VS Code instead. All other supported apps continue to work normally.

## Google Chat

1. Select a message like:
   `Please review this flow and let me know if any changes are needed. https://www.figma.com/design/example`
2. In the OpenClip-style popup, click **Capture Intent**.
3. Confirm a brief "Understanding intent…" loading state (never naming a provider), then the preview appears.
4. Verify: **ACTION**, a "Next action" summarizing the review request, **no deadline** shown
   (unless the source actually contained one), and an **Open Figma** resource link pointing at the
   real URL from the message. Confirm no invented name, date, or company appears anywhere.
5. Click **Track**, then open **Intent Inbox** from the menu bar and confirm the item is under
   **OPEN** (no deadline) with the Figma link visible in the detail view.

## WhatsApp Web

1. Select: `Hi Rahman, can we have a session at 5pm??`
2. Click **Capture Intent**. This must **not** report "No actionable intent detected."
3. Verify: **REQUEST** or **WAITING**, time `5pm` preserved verbatim, and **no invented date** (no
   "today"/"tomorrow" unless the text actually said so).
4. Track it and confirm it appears under **WAITING** in Intent Inbox if the type was WAITING, or
   **OPEN** if REQUEST.

## Safari or Chrome

1. Put `Once Finance confirms the budget, send the proposal to Priya.` on a page or editable field.
2. Select only the sentence and click **Capture Intent**.
3. Verify: **ACTION** (trigger-gated — the condition lives in the "trigger"/waiting-for field, not
   as its own top-level type), trigger `Finance confirms the budget`, target `Priya`.
4. Confirm the source application is Safari or Google Chrome, then Track or Ignore.

## Visual Studio Code

1. Type `Review the authentication refactor on Friday.` in a text file.
2. Select exactly the sentence and click **Capture Intent**.
3. Verify: **ACTION**, deadline `Friday`.
4. Track it and confirm it appears under **TODAY**/**LATER** in Intent Inbox depending on today's date.

## Grounding checks (the most important checks in this milestone)

1. Select `Please review this.` (no date, no name, no link) and Capture Intent. Confirm **no**
   deadline, person, or resource appears anywhere in the preview — only the review action itself.
2. Select `I already sent the deck yesterday.` and Capture Intent. Confirm **"No trackable intent
   detected."** — completed work must never become a new open ACTION.
3. Select `Don't send this to Finance.` and Capture Intent. Confirm **no positive ACTION** is created.
4. Enable **Intent debug details** and re-run step 1's capture. Open the Debug disclosure and
   confirm **GROUNDING EVIDENCE** / **FIELDS REMOVED BY VALIDATOR** are visible and never show the
   API key.

## Privacy and product-copy checks

1. Invoke the global popup with clipboard text but no live selection. Confirm Capture Intent is not available.
2. Run `./scripts/dev_run.sh` from a shell where `GEMINI_API_KEY` is **not** set. Capture Intent on
   any text. Confirm the message **"Intent Intelligence is not configured."** appears and nothing
   is saved — and that it never names "Gemini" (compare against a DEBUG build, where the same
   failure shows the real reason, e.g. "Gemini API key not found...").
3. With Intent debug details **off**, confirm nothing in the normal preview or Inbox UI (footer,
   detail view) ever shows a parser name or model id — only in Debug mode.
4. Force a network failure (e.g. temporarily break connectivity) and confirm the message is
   **"Intent Intelligence is temporarily unavailable."**, never "Gemini API failed" or similar.
5. Enable Intent debug details to inspect/copy source and raw parser data (Provider, Model,
   latency, raw structured output, grounding evidence — never an API key or request headers).
   Disable it to hide those explicit debug surfaces. Routine `metrics.jsonl` must contain no
   source text.
