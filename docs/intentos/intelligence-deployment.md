# Intent Intelligence — deployment architecture

This is a short note on how Intent Intelligence is wired today versus how it must be wired before
any public/shared distribution. It is a statement of direction, not an implementation — the
backend described under "Target production" does not exist yet and is out of scope until IntentOS
is ready to leave prototype/development use.

## Current prototype

```
IntentOS macOS app
  → Gemini API directly (generateContent, structured output)
  → GEMINI_API_KEY supplied by the developer's own shell/Xcode scheme environment
```

- The key lives only in the developer's process environment for the lifetime of that process. It
  is never written to source, UserDefaults, a plist, the Keychain, `SecretStore`, or any log —
  see `IntentIntelligenceConfiguration` and `GeminiIntentParser`.
- Every developer running this build supplies their own key. There is no shared/embedded
  production credential anywhere in the app or its build settings.
- This is explicitly **not suitable for public distribution** with a single shared API key: a
  compiled app cannot keep an embedded credential secret (it can always be extracted from the
  binary or intercepted from the outgoing request), so shipping this arrangement to real users
  would either leak the key or require trusting every installed copy of the app with it.

## Target production

```
IntentOS macOS app
  → authenticated IntentOS backend
  → Gemini (or another provider), credential held server-side
```

The client authenticates to IntentOS's own backend (not to Gemini directly); the backend holds the
provider credential and proxies the structured-output request. This unlocks, without any client
release:

- **Credential protection** — the provider key never ships inside the app or crosses onto a
  user's machine at all.
- **Quotas and usage accounting** — per-user/per-install limits, cost tracking.
- **Model routing** — swap or A/B test providers/models server-side.
- **Rate limiting and abuse controls** — protect the shared credential and the provider account.
- **Provider changes without client releases** — `IntentIntelligenceConfiguration` today
  centralizes the model choice inside the app for exactly this reason (one constant, not scattered
  strings); a backend moves that decision entirely off the client.

Building that backend is a separate, later piece of work. `GeminiIntentParser` already sits behind
the provider-neutral `IntentParsing` protocol specifically so swapping "call Gemini directly" for
"call our backend" later is a new `IntentParsing` conformer, not a rewrite of the capture/preview/
grounding/inbox pipeline that depends on it.
