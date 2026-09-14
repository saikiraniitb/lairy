# Needle 2 baseline benchmark

Dataset: 75 fixed English utterances. Model: official `cactus-needle==2.0.12`, base weights, no fine-tuning. Telemetry disabled.
Control check: the package's own `productivity` acceptance suite passed 28/32 cases on the same engine. The runtime is functional; the abstract IntentOS taxonomy is the mismatch.

## Metrics

- Intent classification accuracy: 22.7% (17/75)
- No-intent precision: 25.0%
- No-intent recall: 15.8%
- Field extraction accuracy: 20.4% (21/103)
- Target extraction accuracy: 18.8%
- Deadline extraction accuracy: 15.8%
- Trigger extraction accuracy: 0.0%
- False-positive rate on no-intent cases: 84.2% (32/38)
- Cold model initialization: 1202.0 ms
- Median warm latency: 106.5 ms
- P95 warm latency: 151.6 ms
- Peak RAM reported/observed: 64.1 MB

Field matching is conservative but allows case/punctuation differences, containment, or at least 75% coverage of expected tokens. Explicit `null` expectations test non-invention.

## Category accuracy

| Category | Passed classification | Passed full record |
|---|---:|---:|
| ambiguous | 25.0% | 25.0% |
| completed | 0.0% | 0.0% |
| follow_up | 20.0% | 0.0% |
| multi_action | 0.0% | 0.0% |
| negation | 25.0% | 25.0% |
| no_intent | 8.3% | 8.3% |
| obvious_do | 7.1% | 0.0% |
| remember | 80.0% | 70.0% |
| third_party | 25.0% | 25.0% |

## Confidence distribution

- <0.50: 74
- 0.50-0.74: 1
- 0.75-0.89: 0
- >=0.90: 0

| Threshold | Accepted calls | Accepted precision | Positive recall | False positives |
|---:|---:|---:|---:|---:|
| 0.50 | 0 | 0.0% | 0.0% | 0 |
| 0.60 | 0 | 0.0% | 0.0% | 0 |
| 0.70 | 0 | 0.0% | 0.0% | 0 |
| 0.75 | 0 | 0.0% | 0.0% | 0 |
| 0.80 | 0 | 0.0% | 0.0% | 0 |
| 0.85 | 0 | 0.0% | 0.0% | 0 |
| 0.90 | 0 | 0.0% | 0.0% | 0 |
| 0.95 | 0 | 0.0% | 0.0% | 0 |

Recommended initial confidence threshold from this corpus: **0.75**, but no emitted intent reached even 0.50. This gate therefore routes every current call to uncertainty; it is a safety default, not evidence of useful calibration for this schema.

## Failure cases

- `do-01` (obvious_do): expected `do`, predicted `remember`, confidence `0.0011`, mismatched fields: action, target, deadline_text — I'll call Ravi tomorrow.
- `do-02` (obvious_do): expected `do`, predicted `do`, confidence `0.0001`, mismatched fields: object — I need to review the roadmap Friday.
- `do-03` (obvious_do): expected `do`, predicted `None`, confidence `0.2142`, mismatched fields: action, object, target — Send the revised deck to Priya.
- `do-04` (obvious_do): expected `do`, predicted `None`, confidence `0.5237`, mismatched fields: action, object, target, deadline_text — Schedule a discussion with Arun next week.
- `do-05` (obvious_do): expected `do`, predicted `remember`, confidence `0.0001`, mismatched fields: action, object, target, deadline_text — I'll send the revised presentation to Rahul by Friday.
- `do-06` (obvious_do): expected `do`, predicted `None`, confidence `0.1428`, mismatched fields: action, object, deadline_text — Review PR 182 tomorrow.
- `do-07` (obvious_do): expected `do`, predicted `remember`, confidence `0.0`, mismatched fields: action, object, target, deadline_text — I need to send the Hiringhood roadmap to Arun tomorrow.
- `do-08` (obvious_do): expected `do`, predicted `None`, confidence `0.2465`, mismatched fields: action, object, target, deadline_text — Schedule a review with Arun sometime next week.
- `do-09` (obvious_do): expected `do`, predicted `None`, confidence `0.3363`, mismatched fields: action, object, target, deadline_text — Email the signed contract to legal by 4 PM.
- `do-10` (obvious_do): expected `do`, predicted `remember`, confidence `0.0`, mismatched fields: action, object, deadline_text — I will book the conference room on Tuesday.
- `do-11` (obvious_do): expected `do`, predicted `None`, confidence `0.2581`, mismatched fields: action, object, deadline_text — Please update the launch checklist today.
- `do-12` (obvious_do): expected `do`, predicted `None`, confidence `0.2823`, mismatched fields: action, object — Draft the Q4 hiring plan.
- `do-13` (obvious_do): expected `do`, predicted `remember`, confidence `0.0`, mismatched fields: action, object, deadline_text — I'll pay the design invoice before Monday.
- `do-14` (obvious_do): expected `do`, predicted `None`, confidence `0.1076`, mismatched fields: action, target, deadline_text — Call the vendor and confirm the delivery window tomorrow.
- `do-15` (multi_action): expected `do`, predicted `None`, confidence `0.1083`, mismatched fields: summary, deadline_text — Review the document and call Arun tomorrow.
- `remember-04` (remember): expected `remember`, predicted `remember`, confidence `0.0`, mismatched fields: subject — Save this detail: Priya's preferred timezone is IST.
- `remember-09` (remember): expected `remember`, predicted `None`, confidence `0.1641`, mismatched fields: summary — Make a note that the API limit is 500 requests per minute.
- `remember-10` (remember): expected `remember`, predicted `do`, confidence `0.0005` — Don't forget that the demo account expires in October.
- `follow-01` (follow_up): expected `follow_up`, predicted `follow_up`, confidence `0.0001`, mismatched fields: deadline_text, trigger — If he doesn't reply by Wednesday, follow up.
- `follow-02` (follow_up): expected `follow_up`, predicted `None`, confidence `0.0231`, mismatched fields: action, target, trigger — Once Finance approves this, send it to the client.
- `follow-03` (follow_up): expected `follow_up`, predicted `None`, confidence `0.0982`, mismatched fields: action, object, trigger — When Ravi sends the numbers, update the forecast.
- `follow-04` (follow_up): expected `follow_up`, predicted `None`, confidence `0.1826`, mismatched fields: action, deadline_text — Check again next Monday.
- `follow-05` (follow_up): expected `follow_up`, predicted `follow_up`, confidence `0.0002`, mismatched fields: trigger — If Finance doesn't approve this by Wednesday, follow up with Priya.
- `follow-06` (multi_action): expected `follow_up`, predicted `None`, confidence `0.1329`, mismatched fields: summary, trigger, target — Once Ravi sends the numbers, update the forecast and send it to Finance.
- `follow-07` (multi_action): expected `follow_up`, predicted `None`, confidence `0.0531`, mismatched fields: summary, trigger, target — When Priya replies, update the deck and forward it to leadership.
- `follow-08` (follow_up): expected `follow_up`, predicted `remember`, confidence `0.0`, mismatched fields: action, object, target, trigger — After the build finishes, send the test report to Maya.
- `follow-09` (follow_up): expected `follow_up`, predicted `None`, confidence `0.0587`, mismatched fields: action, target, deadline_text, trigger — If the vendor has not responded by Friday, call them.
- `follow-10` (follow_up): expected `follow_up`, predicted `None`, confidence `0.1594`, mismatched fields: action, object, trigger — When the contract arrives, review the termination clause.
- `follow-11` (follow_up): expected `follow_up`, predicted `None`, confidence `0.1082`, mismatched fields: action, object, deadline_text, trigger — Revisit the incident after the postmortem next week.
- `follow-12` (follow_up): expected `follow_up`, predicted `do`, confidence `0.0004`, mismatched fields: object, trigger — As soon as Priya shares the draft, add the pricing section.
- `ordinary-01` (no_intent): expected `None`, predicted `remember`, confidence `0.0045` — The weather is good today.
- `ordinary-03` (no_intent): expected `None`, predicted `remember`, confidence `0.0005` — This presentation looks much better.
- `ordinary-04` (no_intent): expected `None`, predicted `remember`, confidence `0.0` — Friday's meeting went well.
- `ordinary-05` (no_intent): expected `None`, predicted `remember`, confidence `0.0001` — The office closes at six.
- `ordinary-06` (no_intent): expected `None`, predicted `remember`, confidence `0.0` — Our roadmap has three workstreams.
- `ordinary-07` (no_intent): expected `None`, predicted `remember`, confidence `0.0` — Priya likes the blue version.
- `ordinary-08` (no_intent): expected `None`, predicted `remember`, confidence `0.0` — The document is in the shared folder.
- `ordinary-09` (no_intent): expected `None`, predicted `remember`, confidence `0.0` — We usually meet on Tuesdays.
- `ordinary-10` (no_intent): expected `None`, predicted `remember`, confidence `0.0` — That was a useful discussion.
- `ordinary-11` (no_intent): expected `None`, predicted `remember`, confidence `0.0` — The revised design uses less memory.
- `ordinary-12` (no_intent): expected `None`, predicted `remember`, confidence `0.0` — September has been unusually busy.
- `negation-01` (negation): expected `None`, predicted `remember`, confidence `0.0001` — Don't remind me about this.
- `negation-02` (negation): expected `None`, predicted `remember`, confidence `0.0` — I don't need to call Rahul anymore.
- `negation-04` (negation): expected `None`, predicted `remember`, confidence `0.0` — We decided not to send the proposal.
- `negation-05` (negation): expected `None`, predicted `remember`, confidence `0.0` — Don't send this to Finance.
- `negation-06` (negation): expected `None`, predicted `remember`, confidence `0.0002` — No need to schedule another review.
- `negation-08` (negation): expected `None`, predicted `remember`, confidence `0.0` — I won't follow up with the vendor.
- `thirdparty-01` (third_party): expected `None`, predicted `remember`, confidence `0.0` — Rahul said he'll send me the document Friday.
- `thirdparty-04` (third_party): expected `None`, predicted `do`, confidence `0.0` — Arun plans to schedule the kickoff next week.
- `thirdparty-05` (third_party): expected `None`, predicted `remember`, confidence `0.0` — The vendor promised to email the invoice today.
- `thirdparty-06` (third_party): expected `None`, predicted `do`, confidence `0.0005` — Maya has to update the dashboard by Monday.
- `thirdparty-07` (third_party): expected `None`, predicted `remember`, confidence `0.0` — Legal is going to send Priya the contract.
- `thirdparty-08` (third_party): expected `None`, predicted `do`, confidence `0.0001` — Ravi should check the numbers again tomorrow.
- `past-01` (completed): expected `None`, predicted `remember`, confidence `0.0` — I sent the deck yesterday.
- `past-02` (completed): expected `None`, predicted `do`, confidence `0.0002` — We finished the migration last Friday.
- `past-03` (completed): expected `None`, predicted `do`, confidence `0.0001` — Rahul already reviewed the document.
- `past-04` (completed): expected `None`, predicted `remember`, confidence `0.0` — I already sent Rahul the deck yesterday.
- `past-05` (completed): expected `None`, predicted `do`, confidence `0.0036` — The team completed the security review this morning.
- `past-06` (completed): expected `None`, predicted `remember`, confidence `0.0003` — I called the client and resolved the issue.
- `ambiguous-01` (ambiguous): expected `None`, predicted `remember`, confidence `0.0021` — Maybe we should revisit pricing sometime.
- `ambiguous-02` (ambiguous): expected `None`, predicted `remember`, confidence `0.0` — Might be worth calling Arun.
- `ambiguous-03` (ambiguous): expected `None`, predicted `remember`, confidence `0.0` — We probably ought to review this later.

## NEEDLE V0 VERDICT

Classification: 22.7%
No-intent handling: precision 25.0%, recall 15.8%
Extraction: 20.4%
False positives: 32 of 38 no-intent inputs
Latency: 106.5 ms median / 151.6 ms p95 warm
RAM: 64.1 MB peak
Confidence usefulness: not useful for accepting this schema's calls; every emitted intent scored below 0.50. A 0.75 safety gate rejects them all.

Verdict: FAIL

Recommended confidence threshold: 0.75

Known failure cases: listed above.
