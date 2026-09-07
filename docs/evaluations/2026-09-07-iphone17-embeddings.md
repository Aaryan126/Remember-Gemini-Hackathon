# iPhone 17 embedding evaluation — 7 September 2026

## Outcome

**Model execution passed; automatic clustering quality failed.** Do not treat the initial cosine thresholds as production-calibrated.

The physical iPhone 17 ran iOS 26.6.1 (23G83). A separately signed app, `SimpleStudio.Remember.EmbeddingProbe`, compiled the current Remember source files directly, excluding `RememberApp.swift`, with a diagnostic entry point. It did not launch ContentView, the capture pipeline, or the live database. It had no Remember App Group entitlement. The installed Remember application and its library were not updated or accessed by the probe.

The probe used synthetic English notes only. Graph tests used fresh temporary SQLite databases, the actual `AppleProjectEmbedding` and `ProjectGraphService`, and an injected reasoner that returns nil. There were no cloud inference calls. Foundation Models reported available, but its generation quality was not tested.

## Measurements

| Check | Result |
| --- | --- |
| Apple model assets | Already available; no download path exercised |
| Contextual model | `5C45D94E-BAB4-4927-94B6-8B5745C46289`, revision 1 |
| Representation | 512 dimensions, production `token-mean-v1` pooling |
| Valid finite unit-length vectors and matching space | 12/12 |
| Nearest neighbor in correct topic | 12/12 |
| First embedding call | 154 ms |
| Subsequent short-note calls | 55–65 ms |
| Long input, 2,379 characters | 341 ms; valid vector |
| Repeat embedding | Cosine approximately 1.0 |
| Empty input | Returned nil as expected |
| Same-topic cosine range | 0.9323–0.9714 |
| Different-topic cosine range | 0.7871–0.9346 |
| Different-topic pairs at or above placement threshold 0.80 | 50/54 |
| Different-topic pairs at or above merge threshold 0.92 | 4/54 |

These timings include production model load/unload calls and are single-run measurements, not performance percentiles. The earlier embedding-only run produced the same similarity matrix, with a 147 ms first call and 56–67 ms subsequent calls.

## Actual graph behavior

The fixture contains four topics with three variants each: calculus/chain-rule revision, sourdough baking, SwiftUI state/navigation, and a Tokyo–Kyoto holiday. Variants resemble a written note, transcript text, and OCR text. No audio or image extraction was exercised.

1. **Grouped arrival order** (all calculus, then bread, then app development, then travel): all 12 notes ended in one mixed-topic cluster. This happened through placement; no merge event was required.
2. **Interleaved arrival order** (one note per topic, then transcript variants, then OCR variants): four clusters remained, but calculus and app development shared one mixed cluster, while one travel note was isolated. One automatic merge event occurred.

Both runs stored 12 real placement vectors. A repeated synchronization added no events, so event-level idempotence passed.

The direct-placement branch accepts a single candidate at cosine ≥0.80 without a competing-candidate margin. These actual vectors allow unrelated captures to join the first cluster; its changing centroid can then absorb further topics. The batch threshold also allows some unrelated pairs to merge. Correct nearest-neighbor rankings alone therefore do not validate this clustering policy.

A diagnostic comparison using Apple's English sentence embedding produced same-topic scores of 0.4434–0.8053 and different-topic scores of 0.0309–0.5100. Those ranges also overlap: this small comparison does **not** validate a replacement model or justify simply swapping models while preserving thresholds.

## Scope and next work

Production code and thresholds were not changed during this testing pass. The evidence supports revising and evaluating the embedding/placement policy before trusting automatic organization, including singleton acceptance, merge criteria, and capture-order sensitivity. A larger held-out corpus should cover intended languages, short/long notes, ambiguous topics, and semantic changes. Foundation Models reasoning, asset downloading, memory/power profiling, and actual media extraction remain unverified on-device.

The separate **Embedding Probe** app remains installed for reruns. It can be removed manually; its data is synthetic and separate from Remember.

## Artifacts and checks

- [Full machine-readable report](2026-09-07-iphone17-embeddings.json).
- Temporary diagnostic project and Swift driver: `/tmp/RememberEmbeddingProbe.kWrB1v/`.
- Successful build log: `/tmp/remember-device-graph-build.log`.
- Successful device execution log: `/tmp/remember-device-graph-run.log`.
- The initial expanded diagnostic build hit a throwing-expression compile error in the probe; that probe-only error was corrected and the subsequent build passed.
- `git diff --check` passed. No production files, Git index, refs, history, or repository configuration were changed during this pass.

The temporary project references the current app and Shared sources, and the already-cached GRDB package. It has no app-group capability. Temporary artifacts are not a permanent test target.

Commands actually used (device identifier omitted here):

```sh
xcrun devicectl list devices --timeout 10
xcodebuild -project Remember/Remember.xcodeproj -scheme Remember -showdestinations
xcodebuild -project /tmp/RememberEmbeddingProbe.kWrB1v/EmbeddingProbe.xcodeproj \
  -scheme EmbeddingProbe -destination 'platform=iOS,id=<connected-device-id>' \
  -derivedDataPath /tmp/RememberEmbeddingProbe.kWrB1v/build \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device <connected-device-id> \
  /tmp/RememberEmbeddingProbe.kWrB1v/build/Build/Products/Debug-iphoneos/EmbeddingProbe.app
xcrun devicectl device process launch --device <connected-device-id> \
  --console --timeout 180 SimpleStudio.Remember.EmbeddingProbe
xcrun devicectl device copy from --device <connected-device-id> \
  --source Documents/embedding-probe.json \
  --destination /tmp/RememberEmbeddingProbe.kWrB1v/final-result.json \
  --domain-type appDataContainer --domain-identifier SimpleStudio.Remember.EmbeddingProbe
git diff --check
```

The diagnostic process exited successfully after writing its report; the report explicitly says `quality_checks_failed`. A successful process exit is not a passing clustering evaluation.

Production source SHA-256 at evaluation:

- `ProjectIntelligence.swift`: `c39deba4e15f363f8c919cd302994310cdb19a5fff3b2e59c5f4b2f81744850d`
- `ProjectGraphService.swift`: `e21723ce1d14242407cd1046184eefa5503d79ed794ab3e483deb89a73d45b5a`
