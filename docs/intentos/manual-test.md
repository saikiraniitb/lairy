# IntentOS V0 manual test

## Prerequisites

1. Install full Xcode 16 or newer and select it in Xcode settings or with `xcode-select`.
2. From `tools/needle-spike`, create `.venv`, install `requirements.txt`, and fetch generation 2 as
   shown in that directory's README.
3. Run `./scripts/dev_run.sh` from the repository root.
4. Grant the built app Accessibility permission in **System Settings → Privacy & Security → Accessibility**.
5. Keep **Needle confidence threshold** at 0.75. The measured base model will normally show these
   cases as uncertain; use **Edit Manually** to correct them.

## Apple Notes

1. Type `I need to send the Hiringhood roadmap to Arun tomorrow.`
2. Select exactly that sentence.
3. In the OpenClip-style popup, click **Capture Intent**.
4. Confirm local loading appears and then an IntentOS preview/uncertain preview appears.
5. Verify or edit: type `DO`, action `send`, object `Hiringhood roadmap`, target `Arun`, deadline
   `tomorrow`. Confirm the original source text and Notes source metadata remain visible.
6. Click **Track**.
7. Open the menu-bar item and choose **Intent Inbox…**. Confirm the item is under OPEN.
8. Quit the app completely, run it again, reopen Intent Inbox, and confirm the item persists.
9. Select the item and click **Mark Done**. Confirm it moves to DONE; click **Reopen** if desired.

## Safari or Chrome

1. Put `Once Finance confirms the budget, send the proposal to Priya.` on a page or editable field.
2. Select only the sentence and click **Capture Intent**.
3. Verify or edit: type `FOLLOW UP`, trigger `Finance confirms the budget`, action `send`, object
   `proposal`, target `Priya`.
4. Confirm the source application is Safari or Google Chrome, then Track or Ignore.

## Visual Studio Code

1. Type `Review the authentication refactor on Friday.` in a text file.
2. Select exactly the sentence and click **Capture Intent**.
3. Verify or edit: type `DO`, action `review`, object `authentication refactor`, deadline `Friday`.
4. Track it and confirm it appears under OPEN in Intent Inbox.

## Privacy checks

1. Invoke the global popup with clipboard text but no live selection. Confirm Capture Intent is not available.
2. Capture `The weather is good today.`. If Needle returns no call, confirm the brief no-intent
   state and no Inbox item. If it returns the measured low-confidence false positive, confirm the
   uncertain UI and choose Ignore; it must not persist.
3. Keep Cloud fallback off. Click Try Cloud AI in an uncertain preview and confirm the app reports
   that cloud fallback is off without sending text.
4. Enable cloud fallback only if a cloud provider/key is configured, then click Try Cloud AI.
   This click is the separate transmission consent boundary.
5. Enable Intent debug details to inspect/copy source and raw parser data. Disable it to hide those
   explicit debug surfaces. Routine `metrics.jsonl` must contain no source text.
