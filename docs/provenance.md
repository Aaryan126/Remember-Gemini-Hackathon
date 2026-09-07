# Provenance and Project

## Changed files

App files below are under `Remember/Remember/`.

- Added: `Provenance.swift`, `ProjectGraphService.swift`, `ProjectIntelligence.swift`, `ProjectViewModel.swift`, `ProvenanceViews.swift`.
- Updated persistence/capture: `MemoryItem.swift`, `MemoryStore.swift`, `MemoryPipeline.swift`, `LibraryViewModel.swift`.
- Updated interface/privacy: `ContentView.swift`, `ProjectView.swift`, `MemoryDetailView.swift`, `SettingsView.swift`, `PrivacyActivity.swift`, `PrivacyDashboardView.swift`.
- Tests: added `Remember/RememberTests/ProvenanceTests.swift`, `ProjectClusteringTests.swift`, `RecordedProjectEmbeddingTests.swift`, and the synthetic `project-embedding-device-v5.json` fixture; updated `Remember/RememberUITests/RememberUITests.swift`. A separate reusable physical-device probe lives under `scripts/embedding-evaluation/`.
- Documentation: updated `readme.md`; added `docs/provenance.md`. The supplied feature spec was not modified.

## Data and recovery

`provenanceEvent` is an append-only GRDB/SQLite ledger with a monotonically increasing sequence, unique event ID, recorded timestamp, source ID, origin, and versioned JSON payload. SQLite triggers reject UPDATE and DELETE. Capture payloads preserve original capture timestamps separately from the event’s recorded timestamp. Capture events include OS and time-zone context without a device identifier.

The `memory` table remains the mutable current-state projection used by Memories and retrieval. Memory changes and their events commit in the same database transaction. Notes edited through the app receive a new protected payload file; old file references remain valid. Restore reuses an immutable previous payload and appends a revision. Files are staged before database references; interrupted captures are retried by stable capture ID. A crash between staging a note revision and recording it can leave an unreferenced file, which is retained rather than risking removal of history.

The additive `createImmutableProvenanceV1` migration backfills existing memories once. These are labelled imported history, recorded at upgrade time; the app cannot reconstruct revisions or classifications overwritten by earlier versions. Legacy Wiki tables remain dormant. Do not delete ledger rows to roll back a correction: use a compensating event. Downgrading to an older app build that predates the ledger is unsupported because it can bypass provenance recording.

Archive replaces memory deletion throughout the app. Originals, extracted content, and events are retained; archived memories are excluded from normal library, collection counts, search, and Ask retrieval. The archive in Project and Settings supports restoration. There is no permanent-erasure action in this version. Storage therefore grows with capture and revision history.

## Local organization

Capture creates a singleton without waiting for models. Local extraction is recorded before generated metadata. Apple Vision, PDFKit/text extraction, and on-device speech produce text; Foundation Models supplies metadata when available. Unavailable or failed generation retains deterministic source-derived metadata.

Project organization keeps two independent local similarity signals: contextual token averages over bounded slices and length-weighted normalized sentence embeddings over sentence-aware, at-most-256-character chunks. Neither score can substitute for the other. The stored space identifies the language, both model revisions/dimensions, contextual model ID, and both pooling strategies. Incompatible spaces are never compared. `semanticVector` is an optional additive JSON payload field, so older ledger events remain readable without a database migration. Empty or unsupported text and missing models retain singleton placement with an explanation. Contextual asset availability triggers a retry, and foregrounding retries pending work; repeated asset requests are throttled.

Automatic decisions also require independent source grounding: at least two shared lemmatized content terms for every affected source pair, excluding generic capture/style words. Identical normalized, meaningful source text is also eligible. This prevents similarly written but unrelated notes from joining solely because their embeddings are close. Source-term evidence is cached by memory ID and exact source text, so edits invalidate it.

`ProjectGraphService` records placement vectors and rationale with their source enrichment/revision event. Sequence checks reject asynchronous decisions computed against older organization. User assignments are pinned and remain intact during automatic placement and merging. Renames survive re-enrichment. Metadata corrections survive generated metadata refreshes until a new content revision.

The current policy is `grounded-dual-v5-place094-margin001-member092-merge095-sem040-cross030-terms2`. Direct placement requires contextual centroid cosine ≥0.94, a ≥0.01 lead among source-grounded candidates, sentence centroid cosine ≥0.40, and support from every member (contextual ≥0.92 and sentence ≥0.30). A candidate cluster must itself be coherent. Bounded reasoning over at most two candidates may handle uncertain matches, including paraphrases without literal term overlap, but the member-level vector guards still apply. Its instructions distinguish a specific topic/project from broad category or writing-style overlap. Uncertain decisions retain the current branch.

Batch review runs after three placements in the first week, twenty thereafter, or on a foreground pass when the last checkpoint is over a day old. Completed event-level work survives cancellation and relaunch. This is foreground/opportunistic work, not a guaranteed nightly background task.

Automatic merging requires contextual centroid similarity ≥0.95, sentence centroid similarity ≥0.40, coherent existing clusters, the source-term gate, and member-level contextual/sentence support for **every cross-cluster pair**, not just centroids. Pinned assignments and rejected pairs prevent automatic merging. Splits of incoherent clusters with at least four sources are proposed when a coherent subgroup can be separated; acceptance checks memberships have not changed. Undo restores affected memberships only when still applicable and preserves unrelated later events. Undoing a merge records a blocked pair and pins affected memberships to prevent immediate recurrence.

The [initial iPhone 17 evaluation](evaluations/2026-09-07-iphone17-embeddings.md) exposed incorrect mixed-topic clustering and capture-order sensitivity in the original policy. The [grounded-policy follow-up](evaluations/2026-09-07-grounded-clustering.md) documents the fix and broader regression results. These remain conservative empirical rules, not probability-calibrated confidence estimates or universal language guarantees. Future policies must use new version identifiers without rewriting past decisions.

Policy/model upgrades regenerate evidence through new placement events. Old-policy vectors are excluded even while an upgrade is only partly complete, and a later unavailable vector invalidates earlier cached evidence. Existing memberships and user pins are preserved; an old mixed cluster can receive a split suggestion but is not silently dismantled. Review and accept such suggestions to correct earlier organization.

## Interface and privacy

Timeline and Graph are peer views inside Project; the selected view persists. Timeline provides topic drill-down plus source/date/topic filters. Graph uses bubbles, shared-source/tag edges, pan/zoom, and a complete accessible topic list; the spatial overview is bounded to forty bubbles. A cluster’s River has tributaries and source/merge events, expandable history, date scrubbing, comparison with today, provenance inspection, and corrections. Historical snapshots replay stored events rather than regenerating content. Weekly recaps retain cited activity IDs and have a deterministic count-based fallback.

Cloud assistance is off by default and affects subsequent capture enrichment, close placement decisions, and broader split suggestions over up to twenty-four sources per topic during batch review. Cloud-proposed splits still require acceptance and are validated against the supplied source IDs. Enabling cloud assistance can transmit source excerpts and images through the existing proxy. Ask and AI search are independent explicit cloud actions; their on-demand embedding cache is separate from graph embeddings. Local capture/bootstrap does not call cloud embeddings. Apple model asset downloads do not send captured text. No billing or paid entitlement is added.

## Validation

```sh
xcodebuild -project Remember/Remember.xcodeproj -scheme Remember \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath /tmp/RememberProvenance CODE_SIGNING_ALLOWED=NO build

xcodebuild -project Remember/Remember.xcodeproj -scheme Remember \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/RememberProvenance CODE_SIGNING_ALLOWED=NO test
```

`ProvenanceTests` covers append-only protection, idempotent captures, retained archives, historical revision replay, stale extraction, merge/revert lineage, split acceptance, vector edge cases, pinned assignments, unavailable models, and a cloud-analyzer spy. The Project UI test captures a note and opens its River, scrubs history, and checks view persistence after relaunch. Existing tests continue covering capture, extraction, search, citation grounding, and manual collections.

Physical-device validation is needed for Apple model availability, asset download behavior, speech, and clustering quality. Cloud reasoning requires a configured proxy and is not exercised by deterministic tests.

### Verified implementation run — 7 September 2026

The simulator build passed. The final regression command below passed **49 unit tests and 3 UI tests (52 total, zero failures)** on iPhone 17 Pro / iOS 26.5. `git diff --check` passed. Exported graph and historical River screenshots were visually inspected.

```sh
xcodebuild -project Remember/Remember.xcodeproj -scheme Remember \
  -destination 'platform=iOS Simulator,id=EC7418D3-29BD-4E1A-BBAD-24037D5420F9' \
  -configuration Debug -derivedDataPath /tmp/RememberProvenance \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:RememberTests \
  -only-testing:RememberUITests/RememberUITests/testProjectCaptureRiverHistoryAndViewPreference \
  -only-testing:RememberUITests/RememberUITests/testRadialCaptureMenuExposesEveryCaptureAction \
  -only-testing:RememberUITests/RememberUITests/testThreeSurfaceNavigationAndTemporaryAI test
```

The simulator reported a permission failure loading Apple’s embedding cache under `/var/db/com.apple.naturallanguaged`. Named singleton fallback, capture, historical browsing, and correction flows continued to work. Real embedding quality, Foundation Models generation, and live cloud reasoning have not been certified by this run. No Git index, refs, history, or repository configuration were changed.

### Physical-device follow-up — 7 September 2026

The separate iPhone 17 probe successfully loaded the real Apple model and checked the actual graph service against synthetic data in temporary databases. Runtime, vector validity, repeatability, and graph idempotence passed; clustering quality failed. In one arrival order all twelve notes from four distinct topics joined one cluster. See the [device evaluation and recorded metrics](evaluations/2026-09-07-iphone17-embeddings.md). The installed Remember app and real library were left untouched, and production behavior was not changed in this diagnostic pass.

### Clustering fix and expanded validation — 7 September 2026

The source-grounded dual-embedding policy subsequently passed nine device arrival-order scenarios across 42 synthetic notes, with no mixed-topic clusters and correct four-topic grouping of the original twelve notes. One unavailable embedding retained a singleton. The expanded unit suite passed 61 tests, and all three UI regressions passed. See the [fix, results, compatibility behavior, and limitations](evaluations/2026-09-07-grounded-clustering.md).

The final clean-harness rerun of the cached implementation also passed all 90 checks after the phone was unlocked, confirming the same nine-scenario results. Its [separate report](evaluations/2026-09-07-grounded-clustering-final-rerun.json) is retained alongside the original evaluation.
