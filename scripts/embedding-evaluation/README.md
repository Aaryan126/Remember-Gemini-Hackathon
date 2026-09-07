# Physical-device clustering evaluation

This probe compiles the production Remember and Shared source files into a **separate app** (`SimpleStudio.Remember.EmbeddingProbe`). It excludes the normal app entry point, Info.plist, assets, and App Group entitlements. It never launches the live library or capture pipeline. Graph tests use disposable databases and a no-decision reasoner, so they cannot call cloud inference.

The 42 synthetic source texts cover fourteen topics. There are nine capture orders, including the original twelve-note regression, reversed orders, interleaved orders, and the expanded corpus. A missing embedding is recorded and must retain its singleton. The report checks source purity, useful grouping (at least 25% fewer clusters than inputs), repeat synchronization, empty input, repeat vectors, and long input. Raw nearest-neighbor errors are reported separately: they are why the production policy needs independent source evidence.

## Prepare

Use an existing GRDB checkout from an earlier Xcode build; preparation does not invoke Git or download dependencies.

```sh
node scripts/embedding-evaluation/prepare.mjs /path/to/existing/GRDB.swift
```

The command prints the generated project, derived-data directory, app path, and isolated bundle identifier. Files are generated in a new temporary directory, not in the repository. The signing team comes from the existing Remember project.

## Build and run

Substitute the paths printed above and the paired device identifier shown by `xcrun devicectl list devices`. The phone must be unlocked, paired, and have Developer Mode enabled.

```sh
xcodebuild -project <generated-project> -scheme EmbeddingProbe \
  -destination 'platform=iOS,id=<device-id>' \
  -derivedDataPath <derived-data> -allowProvisioningUpdates build
xcrun devicectl device install app --device <device-id> <generated-app>
xcrun devicectl device process launch --device <device-id> \
  --console --timeout 300 SimpleStudio.Remember.EmbeddingProbe
xcrun devicectl device copy from --device <device-id> \
  --source Documents/embedding-probe.json --destination <local-report.json> \
  --domain-type appDataContainer --domain-identifier SimpleStudio.Remember.EmbeddingProbe
```

Read the report's `status` and `checks`; process exit alone does not mean the policy passed. The report's `differentTopicPairsPassingBothSignals` field counts pairs passing both model gates **and** the shared-source-term gate. `actualGraphRunsWithoutReasoning` records the resulting clusters. Model availability can vary between OS versions and languages.

The probe also writes `Documents/embedding-fixtures.json`, containing only synthetic texts and their vectors. The committed regression fixture was captured on iPhone 17 / iOS 26.6.1 and rounded to six decimals; it is intentionally static. Refresh it only after inspecting a new model/policy evaluation, not simply to make tests pass.

The probe app remains installed until manually removed. Removing it does not affect Remember.

## Offline regressions

`RememberTests/RecordedProjectEmbeddingTests.swift` replays the recorded vectors through the real graph service without loading Apple embedding models. `ProjectClusteringTests.swift` covers source grounding, vector safety, member-level constraints, stale caches, policy upgrades, pinned assignments, and review-only repair of old mixed clusters. Broader language coverage and real LLM tie-breaking still require separate evaluation.
