# IntentOS V1 manual test

## Prerequisites

1. Install full Xcode 16 or newer and select it in Xcode settings or with `xcode-select`.
2. Run `./scripts/dev_run.sh` from the repository root.
3. Grant the built app Accessibility permission in **System Settings → Privacy & Security → Accessibility**.
4. Open **Preferences → General → Intent Intelligence**, leave **Intelligence Engine** on **Gemini
   Cloud (Recommended)**, paste a Gemini API key, click **Save**, then **Test Connection** to
   confirm it can reach the API before testing capture below.
5. (Optional, for the local/experimental path) From `tools/needle-spike`, create `.venv`, install
   `requirements.txt`, and fetch generation 2 as shown in that directory's README, then switch
   **Intelligence Engine** to **Needle Local (Experimental)** and keep **Needle confidence
   threshold** at 0.75 — the measured base model will normally show these cases as uncertain; use
   **Edit Manually** to correct them.

## Known V1 limitation: Apple Notes

Apple Notes' live-selection retrieval is currently unsupported/unreliable and is **not** a release
blocker for this milestone (see the selection-retrieval investigation elsewhere in this repo's
history). Do not test Notes as part of this milestone's sign-off — use Google Chat, WhatsApp Web,
Safari/Chrome, or VS Code instead. All other supported apps continue to work normally.

## Google Chat

1. Select a message like:
   `Please review this flow and let me know if any changes are needed. https://www.figma.com/design/example`
2. In the OpenClip-style popup, click **Capture Intent**.
3. Confirm a brief "Understanding intent locally…"-style loading state, then the preview appears.
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

## Privacy checks

1. Invoke the global popup with clipboard text but no live selection. Confirm Capture Intent is not available.
2. With no Gemini API key configured, Capture Intent on any text. Confirm the message
   **"Connect Gemini to use Intent Intelligence."** appears and nothing is saved.
3. Confirm the Preferences note reads "Only text you explicitly capture is sent to Gemini for
   interpretation." when Gemini is the active engine, and "No text ever leaves your device." when
   Needle is selected.
4. Enable Intent debug details to inspect/copy source and raw parser data. Disable it to hide those
   explicit debug surfaces. Routine `metrics.jsonl` must contain no source text.
