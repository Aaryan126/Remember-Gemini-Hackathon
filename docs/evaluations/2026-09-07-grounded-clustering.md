# Grounded clustering fix — 7 September 2026

## Result

The source-grounded policy passed the physical iPhone 17 evaluation: **zero mixed-topic clusters in nine arrival-order scenarios**, covering 42 synthetic notes across fourteen topics. The original twelve notes now produce the correct four clusters in both original arrival orders.

The full automated suite passed **61 unit tests and 3 UI tests**. The unit suite includes a replay of the actual device vectors through the real graph service, so these regressions no longer depend on having the phone attached.

## What changed

- `Remember/Remember/ProjectIntelligence.swift`: independent contextual and sentence vectors; sentence-aware bounded pooling; content-term grounding; explicit policy version and similarity guards; specific-topic reasoning instructions.
- `Remember/Remember/ProjectGraphService.swift`: member-level checks for placement/merging, source grounding, policy-aware evidence refresh, invalidation of older cached vectors, cached source-term extraction, and review-only split recovery.
- `Remember/Remember/Provenance.swift`: an optional `semanticVector` field in the existing versioned JSON payload. Old ledger events remain readable.
- `Remember/RememberTests/`: new safety and recorded-vector regression tests, a static synthetic device fixture, and updated provenance fixtures.
- `scripts/embedding-evaluation/`: a reusable isolated device probe and project-preparation script.
- `docs/provenance.md`, this report and its JSON, and the README: behavior, limitations, and verification instructions.

No production database was modified. The installed Remember app was not replaced: testing used the separate `SimpleStudio.Remember.EmbeddingProbe` app, without the Remember App Group entitlement or normal app entry point.

## Why the fix is more than a higher cutoff

The initial contextual-only policy collapsed unrelated subjects. A sentence-only experiment still confused similarly worded notes, and a two-vector-only policy still produced false joins in broader examples. Those failed experiments were not accepted as fixes.

The final policy requires independent evidence: both vector signals, support from individual members rather than only an averaged centroid, and specific shared source terms. Generic capture/style words do not count. Exact normalized meaningful source text also qualifies. This keeps useful grouping while rejecting the observed style-driven false positives.

Apple recommends `NLEmbedding` for semantic similarity; we use sentence embeddings as a separate check, not as a replacement score assumed to be perfectly calibrated. [Apple's contextual embedding documentation](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding)

Current policy: `grounded-dual-v5-place094-margin001-member092-merge095-sem040-cross030-terms2`.

| Decision | Contextual evidence | Sentence evidence | Source-text evidence |
| --- | --- | --- | --- |
| Automatic placement | Centroid ≥0.94; ≥0.01 lead among grounded candidates; every member ≥0.92 | Centroid ≥0.40; every member ≥0.30 | At least two specific shared terms with every member, or identical meaningful text |
| Automatic merge | Centroids ≥0.95; every cross-cluster pair ≥0.92 | Centroids ≥0.40; every cross-cluster pair ≥0.30 | Source grounding for every cross-cluster pair |
| Uncertain placement | Member-level guards still apply | Member-level guards still apply | Bounded reasoning may verify paraphrases without literal overlap; otherwise keep the current thread |

Both existing clusters must also be internally coherent before an automatic merge. Pinned assignments and rejected merge pairs remain protected.

## Device evidence

Device: iPhone 17, iOS 26.6.1 (23G83). Sources are written-note, transcript-like, and OCR-like **text fixtures**, not actual audio recordings or image extraction.

| Corpus/order | Resulting clusters | Mixed-topic clusters |
| --- | ---: | ---: |
| Original 12 notes, grouped | 4 | 0 |
| Original 12 notes, interleaved | 4 | 0 |
| Additional 18 notes, grouped | 6 | 0 |
| Additional 18 notes, reversed | 6 | 0 |
| Full 42 notes, grouped | 16 | 0 |
| Full 42 notes, interleaved | 16 | 0 |
| Full 42 notes, reverse interleaved | 17 | 0 |
| Final 12 added notes, grouped | 6 | 0 |
| Final 12 added notes, reversed | 6 | 0 |

Of the 42 sources, 41 produced valid vectors. One French-heavy source had no available embedding and remained a singleton in every applicable run. Other French-topic sources also remained separate. The reverse-interleaved full run retained one additional iOS singleton. The policy deliberately does not force complete grouping.

Among 780 comparable different-topic pairs, none passed all automatic gates. Raw contextual nearest-neighbor ranking was correct for only 38 of the 41 embeddable sources; that diagnostic is retained in the report rather than treated as proof of clustering quality.

The first embedding call in the passing run took about 158 ms; subsequent short-note calls took approximately 64–77 ms. The 2,379-character input took about 504 ms. These include both embedding signals, are single-run measurements, and are not cold-boot benchmarks or latency percentiles.

Repeated synchronization appended no events in every scenario. The report passed all 90 checks. See the [complete machine-readable results](2026-09-07-grounded-clustering.json).

## History and compatibility

The fix appends new evidence; it does not rewrite old decisions, source files, or ledger events. Policy upgrades refresh old vectors even when source text is unchanged. Old-policy vectors cannot influence a partly completed upgrade, and a later unavailable vector invalidates earlier cached evidence.

Existing memberships and user pins remain intact. Incoherent legacy groups can receive a **split suggestion requiring acceptance**. Existing mistaken groups are not silently dismantled. The tests cover pin preservation, append-only history, latest-vector invalidation, and review-only recovery.

## Verification actually run

- Full unit suite: **61 passed**, including nine recorded-device-vector arrival orders.
- Project River/history/view-persistence, radial capture menu, and three-surface navigation UI tests: **3 passed**.
- Isolated iPhone probe: build and device evaluation passed, with the results above.
- Reusable harness preparation: `node --check scripts/embedding-evaluation/prepare.mjs` and preparation with the existing GRDB checkout passed; the generated project built successfully.
- `git diff --check`: passed.

The additional clean-harness rerun initially could not launch because the phone was locked; two attempts returned `FBSOpenApplicationErrorDomain error 7: Locked`. **Resolved at 15:20 SGT on 7 September:** after the phone was unlocked, the final cached implementation completed successfully and passed all 90 checks. The command was `xcrun devicectl device process launch --device <paired-device-id> --console --timeout 300 SimpleStudio.Remember.EmbeddingProbe`.

The [final rerun report](2026-09-07-grounded-clustering-final-rerun.json) confirms the same cluster counts shown above, zero mixed-topic clusters in all nine scenarios, retained singleton fallback for the unavailable French-heavy source, and no duplicate events on repeat synchronization. The first embedding call took approximately 168 ms and the long input took approximately 532 ms in this run. Its execution log is `/tmp/remember-clustering-final-unlocked-run.log`. The original earlier report is retained separately.

Final production source SHA-256 values verified before this rerun:

- `ProjectIntelligence.swift`: `d1c21473bae4e853b1db61977883441b04e483006b4d3729f05f9d4274b61d36`
- `ProjectGraphService.swift`: `3a29811cd970d8f3525b1fa8271f01584bb37762eded3f1b632e861eab6693d9`

An intermediate test build caught a Swift Testing throwing-expression syntax error; it was corrected before the successful full suite. The first expanded probe stopped on the missing French-heavy embedding; the probe was corrected to test singleton fallback instead of aborting or silently excluding that source. Intermediate model-only policies failed quality evaluation and were superseded.

Commands for the simulator checks:

```sh
xcodebuild -project Remember/Remember.xcodeproj -scheme Remember \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -configuration Debug -derivedDataPath /tmp/RememberProvenance \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:RememberTests test

xcodebuild -project Remember/Remember.xcodeproj -scheme Remember \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -configuration Debug -derivedDataPath /tmp/RememberProvenance \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:RememberUITests/RememberUITests/testProjectCaptureRiverHistoryAndViewPreference \
  -only-testing:RememberUITests/RememberUITests/testRadialCaptureMenuExposesEveryCaptureAction \
  -only-testing:RememberUITests/RememberUITests/testThreeSurfaceNavigationAndTemporaryAI test
```

The runs used the identifier of that simulator rather than its name. Device reproduction is documented in [the probe README](../../scripts/embedding-evaluation/README.md). Verification logs are under `/tmp/remember-clustering-final-tests.log`, `/tmp/remember-clustering-ui-tests.log`, and `/tmp/remember-clustering-grounded-run.log`.

## Limits

The corpus was expanded iteratively; all 42 examples now belong to the regression set, not an untouched final statistical holdout. These results fix the reproduced failure but do not certify arbitrary real-world topics or languages.

The grounding stop-word rules and evaluation are English-focused. Similarity thresholds are empirical gates, not probabilities. Sparse text and paraphrases may remain separate; capture order can still affect fragmentation. The probe deliberately injected a no-decision reasoner, so real Foundation Models tie-breaking and optional cloud reasoning were not certified by this run. Foundation Models reported available, but that is not a generation-quality test.

Asset downloading, speech/image extraction, sustained memory/power use, and large-library performance still need separate device evaluation. The final source includes an evidence cache, verified by the full unit suite and the successful final device rerun, to avoid repeating language tagging for unchanged text.

The separate probe app remains on the phone and can be removed manually without affecting Remember. To use the updated production app, build and run the normal Remember scheme. Review split suggestions for any pre-existing incorrect groups.
