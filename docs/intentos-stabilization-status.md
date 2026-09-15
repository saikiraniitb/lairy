# V1 stabilization status — 16 September 2026

Stabilization work for this session is **complete**. All focused areas verified, full suite
green, changes committed.

## Verified

- Full suite: **1,532 passed, 0 failed** (`/tmp/intentos-full-suite.log`), run once after all
  focused fixes, including the bottom-to-top selection and bare-time UI changes.
- Focused suites re-run individually and all green: `GoogleChatSourceContextResolverTests`,
  `AccessibilitySourceContextResolverTests`, `IntentTemporalResolverTests`,
  `IntentReminderPlannerTests`, `FileIntentRepositoryTests`,
  `IntentCaptureCoordinatorSourceContextSnapshotTests`, `WhatsAppSourceContextResolverTests`,
  `GeminiIntentParserTests`, `IntentGroundingValidatorTests`, `IntentDomainTests`,
  `IntentClassifierTests`.
- WhatsApp / Cherry: captured, tracked, persisted, Inbox inspected, app restarted, Inbox detail
  verified again. No regression from the later source-context/temporal changes — WhatsApp's own
  focused test suite is unaffected. Capture ID `7C0E037C-AADA-42F7-98A0-3741CD7F2E07`, intent ID
  `743F9581-D0B3-4C09-831D-D2297101190D`. WAITING; Connect with Cherry; waitingFor Cherry; event
  16 September 2026 08:00 Asia/Kolkata; deadline/due/follow-up nil; exact source preserved.
- Google Chat / Product Team: fresh user-assisted capture `E109A7A7-F54E-439A-81F7-ABAFA4451B4B`
  (intent `048D5D3E-002E-4100-A3B6-DCBBE13C05F7`) persisted and reloaded with the exact expected
  state — confirmed directly against `~/Library/Application Support/IntentOS/intents.json`:
  `type=waiting`, `status=waiting`, `summary=Update the Coding Assessment document`,
  `subject=Coding Assessment`, `waitingFor` absent (nil, correctly — a space title is not a
  person), no `deadline`/`dueAt`/`eventAt`/`followUpAt`, exact original selected text preserved.
- Notification cleanup for the same intent: log analysis of `~/Library/Logs/OpenClip/openclip.log`
  confirms `scheduleReminder` (which unconditionally calls
  `removePendingNotificationRequests` before evaluating the plan) ran on every subsequent
  status/update call up through the final restore-to-WAITING edit (matching the intent's
  `updatedAt`). No further scheduling occurred after that. No stale pending reminder remains for
  `048D5D3E-002E-4100-A3B6-DCBBE13C05F7`.
- Bare meeting time → eventAt: `IntentTemporalResolverTests.testWaitingWithMeetingTimeProducesEventAtNotFollowUp`
  and `testMeetingWordingWithTimeProducesEventAt` cover "bare time + meeting wording, user picks
  Today/Tomorrow → eventAt, never dueAt/followUpAt even when type == WAITING". Both pass.

## Notes for future sessions

- Generic (uncalibrated) AX fallback intentionally returns only source app and selected text —
  no guessed group participants, no borrowing another frontmost app's metadata.
- Basic notification quick actions are **not implemented** (out of scope, do not add).
- Future product design only, not implemented: `intentos-next-layer.md`.

## Runtime notes

Build: `./scripts/dev_run.sh`; tests: `./scripts/test.sh` (regenerate with xcodegen after new files).
Run tests and live checks sequentially: Xcode tests use the app host.
Gemini key exists in the process environment; never print it.
App: `/Users/saikiran/Library/Developer/Xcode/DerivedData/OpenClip-aatlkbekvqwaexhfhidfvevfkemh/Build/Products/Debug/OpenClip.app`.
Logs: `~/Library/Logs/OpenClip/openclip.log`.
Data: `~/Library/Application Support/IntentOS/intents.json`.

The user approved `tools/intentos-input.swift` as a system-wide GUI helper, then offered
to perform selections/Capture Intent when needed. Sky coordinates are app-relative and
screenshots are scaled; actual screen is 1470×956, WhatsApp window starts at (0,33).
Use the app's full path with Sky; its display name/bundle can be ambiguous.
To open Inbox, System Events can click menu bar item 1 of menu bar 2 of process OpenClip,
then its menu item `Intent Inbox…`.

New repository dates use `{referenceSeconds: Double}` to preserve exact Date equality;
legacy Unix/ISO formats remain readable. Older binaries cannot read the new representation.
