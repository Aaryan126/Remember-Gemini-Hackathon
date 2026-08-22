# Remember implementation

## Scope of this vertical slice

This implementation turns the original Gemma smoke test into the first usable Remember workflow:

1. A user shares an image or text to the Share Extension.
2. The extension quickly writes the raw capture to the shared App Group and exits. It never loads Gemma.
3. When the main app becomes active, it imports pending captures into protected app-local storage.
4. The app extracts image text with Apple Vision, sends the original image and supporting text to Gemma 4 E2B through MLX, and asks for a title, summary, and tags.
5. The memory moves through visible `captured`, `processing`, `indexed`, or `failed` states.
6. The user sees memories in a visual library and can inspect, correct, retry, or delete them.
7. Indexed memories receive persisted BGE Micro embeddings as well as a local search document. Submitted natural-language queries combine semantic similarity, exact text, Gemma expansion, and filters.
8. “Ask Remember” searches the compiled Living Wiki first, drills into its original source memories, asks Gemma for a grounded answer, and exposes the cited memory cards.
9. A privacy dashboard records content-free local AI activity metadata and explains the app's actual network boundary.
10. The Share Extension accepts images, text, web links, and PDFs without fetching remote content.
11. The main app records voice memories, transcribes them with an already-installed iOS on-device speech model, then sends only the local transcript to Gemma for title, summary, tags, search, and Ask Remember.
12. An Organize tab creates, renames, and deletes non-owning collections, manages membership, and browses, renames, or removes tags across the library.
13. The versioned Private Project Memory program compiles durable project knowledge, protects every new patch with deterministic checks, runs read-only structural linting, records Research History, and exports an open Markdown projection.

This is deliberately not the full PRD. In-app camera/typed capture, scanned-PDF OCR, guaranteed background scheduling, proactive resurfacing, first-launch model delivery, full binary-vault backup, and delete-all tooling remain future slices.

## High-level architecture

```text
iOS share sheet
      |
      v
RememberShareExtension
      |
      | atomic raw capture (no model inference)
      v
App Group/CaptureInbox
      |
      | foreground import, acknowledge only after durable insert
      v
Application Support/Remember
  +-- Originals/<capture UUID>.<extension>
  +-- remember.sqlite
      |
      | one-at-a-time processing queue
      v
Apple Vision OCR + Gemma 4 E2B via MLXVLM
      |
      v
title + summary + tags + extracted text -> SQLite + lexical text + BGE Micro vectors
                                             |
natural-language query -> hybrid local ranking -> source cards/detail
                                                        |
                                                        +-> Living Wiki -> source memories -> grounded Gemma answer

in-app microphone -> protected local M4A -> installed on-device SpeechTranscriber
                                                   |
                                                   v
                                              local transcript -> Gemma analysis

Organize UI -> collections + membership join table / normalized memory tags
```

The extension and app share only the lightweight `CaptureInbox` code and App Group entitlement. MLX and GRDB are linked only to the main app. This preserves the key memory-boundary requirement in PRD section 6: model inference cannot run inside an iOS Share Extension.

### Runtime dependencies

- `mlx-swift-lm` is pinned to upstream revision `68947ccdca79bcf7a26dc220f73caa060369513c`, including `MLXVLM`. This revision loads the local MLX-format Gemma 4 multimodal model, performs generation through Metal, and contains the E-series shared-KV loader fix that is not present in release 3.31.4.
- `mlx-swift` 0.31.6 is resolved transitively by `mlx-swift-lm`.
- `MLXEmbedders` from the same pinned package loads the bundled MIT-licensed `TaylorAI/bge-micro-v2` BERT checkpoint. Its 34 MiB of files produce normalized 384-dimensional vectors and use approximately 70 MiB while loaded.
- GRDB 7.11.1 provides the SQLite database pool, migrations, records, and transactions.
- Apple Vision performs accurate on-device OCR before the multimodal prompt. OCR supplements the image; Gemma still receives the original image.
- Apple Speech `SpeechTranscriber` performs voice-to-text entirely on device. Remember uses only a locale model that is already installed and does not request an asset download. Gemma remains the language-understanding model that summarizes, tags, indexes, searches, and answers from the transcript.
- Gemma performs natural-language query expansion, wiki reconciliation, and grounded answer generation. BGE Micro performs semantic retrieval; Apple Natural Language embeddings and Apple Foundation Models are not used.
- SwiftUI and Observation implement the app UI and observable library state.

All versions are pinned in `Remember/Remember.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

The revision pin is intentional. Gemma 4 E2B has 35 text layers and shares K/V projections across its final 20 layers, so the checkpoint correctly omits `k_proj`/`v_proj` tensors beginning at layer 15. Released `mlx-swift-lm` 3.31.4 incorrectly declared those modules in the VLM path and failed strict weight loading. Upstream revision `68947ccd` makes the module tree honor `num_kv_shared_layers`; replace the revision with a stable version only after that fix appears in a release.

The iOS development bundle uses a locally derived `~/models/gemma-4-e2b-vision` checkpoint. `scripts/prune_gemma4_for_ios.py` creates it from the original download without fetching or changing model values used by text or vision. It removes only `audio_tower.*` and `embed_audio.*`, which the current `MLXVLM.Gemma4` implementation does not instantiate and discards in its sanitizer. This reduces tensor storage and load pressure by approximately 583 MiB. The original `~/models/gemma-4-e2b` directory remains unchanged.

Before inference, Remember limits MLX's reusable Metal buffer cache to 20 MiB. Each analysis uses a temporary `ModelContainer`; after the result or error, the container is released and `MLX.Memory.clearCache()` runs. This trades a slower cold load per memory for a substantially lower idle footprint and prevents successive analyses from accumulating GPU cache under iOS's process memory ceiling.

The embedder has an 8 MiB MLX cache limit and a 256-token input cap. `GemmaExecutionGate` serializes both model families: BGE loads, embeds, releases, and clears its cache before the 2.8 GiB Gemma checkpoint is allowed to load. The two models are therefore never intentionally resident together.

The main `Remember` target also enables Apple's **Increased Memory Limit** capability (`com.apple.developer.kernel.increased-memory-limit`). The entitlement is intentionally absent from `RememberShareExtension`, which never loads MLX. This capability is required for the current approximately 2.8 GiB vision checkpoint plus Metal working memory and is available only on supported physical devices.

### Local data ownership and privacy

- The App Group `group.SimpleStudio.Remember` is an inbox, not the long-term library.
- After import, original files and `remember.sqlite` live in the main app's Application Support container, outside the extension's shared container.
- Inbox directories are written using a staging directory and atomically renamed when complete.
- Library files are first copied to a staging path and atomically renamed.
- File protection is `completeUntilFirstUserAuthentication`, allowing normal post-unlock operation while retaining iOS Data Protection.
- No captured text, OCR, prompt, response, or image is logged.
- Voice audio is recorded to a temporary AAC/M4A file, with a linear-PCM CAF fallback for device compatibility, atomically copied into protected Application Support storage, and removed from the temporary directory after the durable save.
- Microphone and Speech Recognition permission are requested only when the user starts a voice capture. A denied permission produces an actionable local error.
- The implemented processing path has no application-level upload or remote inference call. Model weights are bundled for development and loaded by local file URL.

The Privacy tab reports the implemented boundary: Remember has no application networking feature, local model loading uses a bundled directory URL, and every analysis/search/chat operation is logged without content. It also states the platform limitation explicitly: iOS does not expose a complete live per-app packet log to the app itself. The UI therefore does not misrepresent a self-reported application boundary as a device-level packet capture.

## Low-level implementation

### Capture and acknowledgement

`Shared/CaptureInbox.swift` owns the cross-target wire format:

- `CapturedItemRecord` contains a schema version, UUID, timestamp, kind, state, caption, and safe payload filename.
- Images, text, URLs, and PDFs are written under `CaptureInbox/.<UUID>.staging` and become visible only after the directory is renamed to `CaptureInbox/<UUID>`.
- Directory names, schema versions, filenames, and payload presence are validated before reading.
- `remove(_:)` only accepts the exact UUID child under the inbox root and is idempotent.

`RememberShareExtension/ShareViewController.swift` accepts shared images, text, web URLs, and one PDF. For a file plus a compose caption, the file is the payload and the compose text is saved as the user's note. URLs are stored as text without opening or fetching them. The extension completes only after the atomic inbox write succeeds.

### Durable import

`CaptureImporter` and `LibraryFileStore` perform an ordered, retry-safe handoff:

1. Enumerate complete inbox records.
2. If the capture UUID is already in SQLite, remove the stale inbox record and continue.
3. Copy its payload to `Originals/.<UUID>.<ext>.staging` and atomically rename it.
4. Insert the `captured` database record if it does not exist.
5. Remove the App Group inbox directory as the acknowledgement.

If the process stops after the file copy but before the database insert, the same stable filename is reused on retry. If it stops after the database insert but before acknowledgement, UUID detection removes the duplicate inbox record without creating a second memory.

### SQLite model and state machine

`MemoryStore` owns a GRDB `DatabasePool` and a versioned `DatabaseMigrator`. The `memory` table stores:

| Column | Purpose |
| --- | --- |
| `id` | Capture UUID and idempotency key |
| `kind` | `audio`, `image`, `link`, `pdf`, or `text` |
| `createdAt`, `importedAt`, `updatedAt` | Capture and lifecycle timestamps |
| `state` | `captured`, `processing`, `indexed`, or `failed` |
| `originalFilename` | Stable filename inside protected Originals storage |
| `userCaption` | User-provided context from the Share Sheet |
| `title`, `summary`, `tagsJSON` | Generated fields, editable by the user |
| `extractedText` | Vision OCR or saved text used during analysis |
| `processingError` | Bounded, user-displayable failure reason |
| `modelVersion` | Analyzer provenance for the generated result |

Records are ordered reverse-chronologically for the library. Queue claims occur inside a database write transaction: the oldest `captured` record becomes `processing` before it is returned. A clean completion becomes `indexed`; a model/OCR failure becomes `failed`. An interrupted `processing` item is reset to `captured` at the next bootstrap so it cannot remain stuck forever.

The `memorySearchIndex` table is a one-to-one, cascade-deleted companion to `memory`. It stores the searchable document text, source update timestamp, 384-dimensional Float32 embedding blob, and index model identifier. The source timestamp or model identifier invalidates the index whenever a generated/user-edited field or embedding model changes. Existing indexed memories are embedded during bootstrap, so this migration does not require users to re-share content. If embedding is temporarily unavailable, lexical retrieval remains usable and the missing vector is retried later.

The `localAIActivity` table records operation kind, timestamps, status, optional memory ID, source count, model version, and a bounded non-content failure category. It deliberately excludes prompts, images, OCR, URLs, answers, and filenames. Running records become `interrupted` only during the first bootstrap of a new pipeline/process.

The `memoryCollection` table stores collection UUIDs and user-editable names. `memoryCollectionMembership` is a composite-key join table with cascading foreign keys. Collections never own memory rows: deleting a collection removes only its memberships, while deleting a memory automatically removes that memory's memberships. Collection names are normalized, bounded, and checked case-insensitively for duplicates.

Tags remain normalized JSON on each memory so Gemma output and manual edits use the same source of truth. The Organize tab derives tag counts from the library. Global rename/delete operations update every matching memory transactionally and immediately rebuild affected local search documents.

### Voice recording and transcription

`VoiceRecorder` owns the explicit microphone session and records single-channel AAC audio to an app temporary file, falling back to linear PCM if the device rejects the AAC encoder configuration. The capture sheet represents permission, idle, recording, recorded, saving, and failure states; prevents accidental dismissal while recording; and deletes abandoned temporary recordings.

After Save, `MemoryPipeline.createVoiceMemory` copies the local audio file into the protected Originals directory before inserting the `captured` SQLite row. Queue processing then:

1. verifies that `SpeechTranscriber` supports the current locale and that a compatible locale model is already installed;
2. transcribes the local audio file with the `.transcription` preset and records content-free transcription activity metadata;
3. passes the bounded transcript to the existing Gemma analyzer as the only semantic source;
4. stores the transcript as `extractedText`, followed by Gemma's title, summary, and tags;
5. indexes those fields for exact search, Gemma-expanded search, and grounded Ask Remember retrieval.

The pinned MLX Swift Gemma 4 VLM implementation does not currently instantiate Gemma 4's audio tower. Remember therefore does not pretend Gemma performed speech recognition: the detail and Privacy screens identify the installed on-device speech transcriber separately from Gemma analysis. No Apple Foundation Models language generation is used.

### Collections and tag management

The **Organize** tab has two local-only sections:

- Collections can be created, browsed, renamed, and deleted. A selection sheet adds or removes any saved memory, and an empty state explains how to populate a collection.
- Tags show library-wide counts and link to matching memories. Swipe actions rename a tag everywhere or remove it everywhere after destructive confirmation.

All organization edits reuse `LibraryViewModel` and `MemoryPipeline` boundaries. SwiftUI never opens the database directly, and collection/tag errors flow through the same user-visible error channel as other library mutations.

### Natural-language retrieval

`MemorySearchService` builds a bounded search document from Gemma-generated title/summary/tags plus user caption and OCR/PDF text. Exact local matching remains immediate while the user types. When the user submits the query or taps **Search with Gemma**, Gemma creates bounded query expansions, releases, and then BGE Micro embeds the original question for a hybrid local scan.

Ranking is hybrid rather than vector-only:

- BGE Micro cosine similarity bridges paraphrases and concepts with no Apple or hosted embedding model;
- Gemma query expansion adds likely synonyms, entities, and categories for lexical recall;
- normalized phrase and token coverage preserves exact names, room numbers, OCR fragments, titles, and tags;
- semantic, original-query, and expanded-term scores are combined, then ties are ordered by recency;
- type, date-range, and tag filters are applied before results are returned;
- if Gemma fails or is not invoked, exact local retrieval and every filter continue to work.

Search is a brute-force scan across bounded local documents. This matches the PRD's expected phone-scale library and avoids adding a network service or dedicated vector database. Gemma and BGE load only for an explicitly submitted semantic query; keystroke-level matching never loads either model.

### Grounded Ask Remember

The Ask tab now performs two-stage retrieval. It first searches `wikiPageSearchIndex` with BGE Micro plus lexical title/alias/summary matching. It then follows the ranked pages' `wikiEvidence` links in round-robin order so one heavily sourced page cannot crowd out every other relevant page. At most eight immutable source memories become the citations. If no relevant compiled page has evidence, Ask falls back to hybrid raw-memory retrieval.

Gemma receives the matching page syntheses as navigation context and the bounded original memories as evidence. The prompt explicitly says wiki pages are evolving synthesis rather than independent evidence, forbids outside knowledge, and permits citations only as `[M1]`, `[M2]`, and so on. Each answer displays tappable original-memory cards. If neither the wiki nor raw retrieval finds evidence, the app returns a deterministic “not found” response without loading Gemma.

`GemmaExecutionGate` serializes analysis, semantic search, and chat. This prevents two UI tasks from loading competing model instances beyond the iPhone memory ceiling. Every operation releases its temporary container and clears the MLX cache afterward.

### OCR and Gemma analysis

`GemmaMemoryAnalyzer` conforms to the small `MemoryAnalyzing` boundary and is an actor, so the cached model container and generation calls are serialized.

For an image:

1. `VisionTextRecognizer` runs `RecognizeTextRequest` with accurate recognition and language correction.
2. `GemmaModelBundle` validates the local folder and required VLM/tokenizer files.
3. `VLMModelFactory` loads `gemma-4-e2b-it-4bit` from the app bundle using the Hugging Face tokenizer loader.
4. `ChatSession` receives both the original local image URL and a bounded prompt containing the user note and OCR.
5. Generation is deterministic (`temperature: 0`) and capped at 280 tokens.

The prompt requests one strict JSON object with a short title, factual summary, and two to six tags. `MemoryAnalysisParser` extracts the first complete JSON object even if the model adds Markdown, normalizes and bounds fields, de-duplicates tags, and falls back to the user note/OCR if the model output is malformed. OCR persisted to SQLite is capped at 50,000 characters, and error strings are capped at 500 characters.

Processing is deliberately sequential to avoid loading multiple multimodal generations into limited iPhone memory at once. The model container is scoped to one analysis and released afterward; this incurs a cold-load cost for every item but avoids keeping roughly 2.8 GiB of model arrays resident while the user browses the library.

### Coordination and UI

`MemoryPipeline` composes the inbox, importer, file store, database, and analyzer. It exposes task-sized operations rather than leaking database or model details into SwiftUI.

`LibraryViewModel` is main-actor isolated. On launch, foreground activation, or pull-to-refresh it:

1. Recovers interrupted work.
2. Imports new App Group captures.
3. Reloads the library so `captured` items appear immediately.
4. Claims and analyzes one item at a time, reloading after every transition.

The `isSynchronizing` guard prevents overlapping foreground and view lifecycle tasks.

`ContentView` is a five-tab shell while Project Memory is enabled: **Memories**, **Project**, **Ask**, **Organize**, and **Privacy**. Disabling Project Memory restores the original four-tab v1 shell. The Memories tab remains a reverse-chronological, two-column visual library. It includes:

- an always-visible search field with instant exact matching and explicit Gemma semantic submission;
- horizontally scrollable type, date, and tag filters with a one-tap clear action;
- ranked source cards plus private/on-device, searching, result-count, and no-result states;
- local image thumbnails downsampled with ImageIO instead of decoding full-resolution images into grid cells;
- empty, opening, processing, failure, and ready states;
- a persistent on-device/lock label;
- pull-to-refresh and foreground inbox pickup;
- navigation to a memory detail view;
- interactive keyboard dismissal when scrolling, background-tap dismissal in chat, and an explicit keyboard Done action in editable forms;
- explicit first-capture instructions covering screenshots, photos, links, PDFs, text, and voice.
- a microphone action that opens explicit voice recording and permission states.

`MemoryDetailView` shows the original, generated summary, tags, OCR disclosure, timestamps, storage location, and model version. Title, summary, and comma-separated tags are editable. Failed analysis can be retried. Delete uses confirmation and removes both the SQLite record and original library file.

## Validation and tests

`RememberTests.swift` contains deterministic coverage for:

- complete/incomplete local model folder validation;
- atomic image and text capture behavior;
- ignoring incomplete inbox staging/data;
- inbox acknowledgement/removal;
- exactly-once importer behavior across repeated calls;
- SQLite claim, indexed-state, OCR/provenance, and editable-field persistence;
- JSON extraction from Markdown-wrapped model output;
- safe parser fallback for malformed output.
- deterministic ranking with injected Gemma-expanded terms;
- persisted search-index creation and backfill;
- type, date, and case-insensitive tag filtering;
- exact local text retrieval without embeddings;
- Float32 embedding serialization and cosine scoring;
- semantic paraphrase retrieval with an injected deterministic embedder;
- Gemma expansion parsing and bounding;
- content-free activity-log completion and interrupted-work recovery;
- atomic URL and PDF capture without network fetching.
- atomic local audio import and transcript-based voice analysis parsing;
- collection membership, non-owning collection deletion, and case-insensitive naming;
- global tag rename/delete behavior and updated tag counts.
- hybrid Living Wiki retrieval combining semantic, lexical, alias, and graph signals;
- round-robin recovery of original wiki evidence memories for citations.
- Private Project Memory schema/version exposure;
- protected patch keep/discard behavior, including duplicate-target rejection;
- balanced compiler JSON extraction when valid payloads are surrounded by prose, fences, or unrelated brace objects;
- deterministic whole-wiki lint failures and healthy invariants;
- append-only run/check/revision linkage and open Markdown projection content.

Commands used during implementation:

```sh
xcodebuild -resolvePackageDependencies \
  -project Remember/Remember.xcodeproj \
  -scheme Remember

xcodebuild -quiet \
  -project Remember/Remember.xcodeproj \
  -scheme Remember \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  build

xcodebuild -quiet \
  -project Remember/Remember.xcodeproj \
  -scheme Remember \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  build-for-testing
```

Package resolution, the app build, compilation of the test bundle, and signed physical-device builds completed successfully. After adding the compiler JSON recovery boundary, the unsigned generic iOS build completed successfully and the full current deterministic unit-test target passed on an iOS 26.5 simulator; simulator tests inject a fake embedder and do not claim to validate real Metal inference, Gemma, or live microphone transcription. The original full checkpoint reproduced an iOS `EXC_RESOURCE (RESOURCE_TYPE_MEMORY)` high-watermark stop at approximately 3.38 GiB. Inspection found approximately 2,483 MiB of language tensors, 320 MiB of vision tensors, and 583 MiB of unused audio tensors. The generated vision-only checkpoint was independently opened with `safetensors` 0.7.0 and contained 1,757 tensors: 1,096 language tensors, 661 vision tensors, and zero audio tensors. The optimized 2.9 GB app was built after enabling Increased Memory Limit, and `codesign -d --entitlements -` confirmed the signed executable contains both `com.apple.developer.kernel.increased-memory-limit = true` and the Remember App Group. A simulator is not an equivalent inference test for model execution.

## Physical iPhone acceptance test

1. Reconnect and unlock the iPhone, then trust the Mac if prompted.
2. In Xcode's top toolbar select the **Remember** app scheme, not `RememberShareExtension`, and select the physical iPhone.
3. Run the app once with **Command-R**. Leave it foregrounded until any existing captured item finishes analyzing.
4. In Photos, choose a clear screenshot or photo, tap Share, choose Remember, add an optional note, and tap Post.
5. Return to Remember. The item should appear and advance from Captured/Analyzing to Ready.
6. Open the card and verify that the original image, generated title, summary, tags, OCR disclosure, and model version are present.
7. Tap Edit, correct a field, save, leave the detail screen, and reopen it to confirm persistence.
8. If analysis fails, use Retry and keep the app foregrounded while the model runs.
9. Search for a concept using different wording from the title, then verify the relevant source card ranks first.
10. Exercise the image/text, date, and tag filters and use Clear to return to the full library.
11. Submit a differently worded query with the keyboard Search button and wait for the **Gemma** result indicator.
12. Open **Ask**, show the keyboard, and verify tapping the conversation or dragging it down dismisses the keyboard. Ask a question supported by a saved memory and verify the answer cites and links to its source card.
13. Open **Privacy** and verify the search/chat operation appears without prompt or answer content.
14. Share a URL and a text-based PDF, return to Remember, and verify both are analyzed locally. Scanned-image PDFs are not OCR'd in this slice.
15. Tap the microphone in Memories, grant Microphone and Speech Recognition access, record a short sentence, stop, and save it.
16. Verify the new voice card advances through transcription and Gemma analysis, then open it to play the local audio and inspect the transcript.
17. Open Privacy and verify separate Voice transcription and Memory analysis records contain metadata but not transcript content.
18. Open Organize, create a collection, add and remove memories, rename it, and delete it; verify its memories remain in the main library.
19. In Organize, rename and delete a tag and verify every affected memory and search result updates.

Every analysis can take noticeably longer because Remember intentionally reloads the approximately 2.8 GiB vision-only model and releases it after the item finishes. This is a deliberate stability tradeoff for the current iPhone memory ceiling.

## Next recommended slice

The next remaining PRD work is in-app typed/camera capture, scanned-PDF OCR, full-vault backup/delete-all, proactive resurfacing, and opportunistic background queue scheduling. A bounded AutoLab evaluation corpus for compiler prompt experiments is the next Private Project Memory quality slice; unbounded autonomous research is intentionally out of scope for the current small on-device model. The current bundled approximately 2.9 GB Gemma app plus 34 MiB embedder is appropriate for development sideloading but should become a first-launch local asset installation flow before App Store distribution.

## Current product status — 22 August 2026

| Area | Status | Notes |
| --- | --- | --- |
| Share capture | Implemented | Images/photos, text, links, and PDFs use the low-memory App Group handoff. |
| Voice capture | Implemented | Explicit recording, installed on-device transcription, Gemma analysis, playback, and searchable transcript. |
| Image understanding | Implemented | Original image plus Vision OCR go to local Gemma. |
| Natural-language retrieval | Implemented | BGE Micro vectors + lexical/title/tag/OCR matching + optional Gemma expansion. |
| Private Project Memory | Implemented foundation | Automatic Living Wiki, project schema, protected patch gates, structural linting, Research History, open Markdown projection, and reversible v1 toggle. |
| Ask | Implemented | Wiki-first retrieval, original-memory drill-down, Gemma answer, and tappable citations. |
| Collections and tags | Implemented | Local collection membership and global tag management. |
| Privacy/activity UI | Implemented with platform caveat | No application networking path; content-free local activity log. iOS does not expose a complete packet log to the app. |
| In-app typed note and camera | Not implemented | Still required by PRD 4.1. |
| Scanned-PDF OCR | Not implemented | Text PDFs work; image-only PDF pages are not yet rendered/OCR'd. |
| Export and delete-all | Partial | Open derived knowledge + research ledger export is implemented; full binary-vault backup and delete-all remain. |
| Proactive resurfacing | Not implemented | PRD v2 item. |
| Background scheduling | Not implemented | Foreground queues are automatic; iOS background execution needs a best-effort scheduler and must remain retry-safe. |
| Production model delivery | Not implemented | Both models are offline local bundles for development; first-launch installation/progress is still needed. |

No routine classification or wiki-routing task is assigned to the user. Gemma decides page type, create-versus-update, effect, aliases, and links from a bounded candidate set; deterministic code enforces safety and persistence. Human input is reserved for optional corrections and explicit retries after failures.

## Living Wiki v2 foundation

Remember now has an additive, reversible Living Wiki layer inspired by Karpathy's persistent LLM Wiki pattern and A-MEM's dynamically linked memory approach. It does not replace the original memory library. Raw captures remain the immutable source of truth, while Gemma maintains a separate derived Private Project Memory layer: projects, decisions, constraints, experiments, feedback, people, open questions, and supporting reference knowledge.

### Returning to v1

The original experience remains available without restoring files or migrating the database:

1. In **Memories**, open the trailing ellipsis menu and turn off **Project Memory**; or open **Privacy → App experience** and turn it off there.
2. The Project tab disappears and Remember returns to the v1 tabs and behavior: Memories, Ask, Organize, and Privacy.
3. Existing memories, search records, collections, chat behavior, and the capture pipeline are unchanged.
4. Wiki pages and revision history remain stored locally. Re-enabling the switch restores them immediately.

Disabling the feature stops future automatic compilation. It intentionally does not delete wiki data. This runtime boundary is the rollback mechanism because this directory is not currently a Git repository and repository policy prohibits agents from creating or changing Git state.

### Compiler flow

After a memory reaches the existing `indexed` state:

1. `MemoryStore.prepareWikiCompilationQueue()` creates or refreshes an additive queue record keyed by the memory UUID and its `updatedAt` timestamp.
2. The queue transactionally claims one memory. Interrupted work returns to `pending` on the next bootstrap; a model or validation failure becomes visible as `failed` without changing the source memory.
3. `WikiSearchService` keeps a companion embedding record for every page and embeds the new memory with BGE Micro. `LivingWikiCandidateIndex` combines cosine similarity with exact titles, aliases, title/summary token overlap, and accumulated page metadata.
4. The top direct matches expand through one graph hop so an already-linked decision or constraint can accompany a matching project even when its wording is different.
5. At most eight candidates are included in the Gemma prompt. Gemma never receives the entire wiki.
6. `GemmaLivingWikiCompiler` returns a strict JSON patch containing at most three high-value page changes. Candidate UUIDs must exactly match the locally supplied allowlist; invented IDs and malformed entries are discarded.
7. `ProjectMemoryPatchEvaluator` runs deterministic protected checks, filters obvious type mismatches, redirects semantically equivalent new pages to retrieved canonical pages, and collapses duplicate proposals. Unsafe or empty proposals are recorded and discarded without wiki mutation; accepted proposals continue to persistence.
8. `MemoryStore.applyWikiCompilation` writes pages, source evidence, page links, run-linked revisions, and the compilation completion marker in one SQLite transaction.
9. After a foreground compilation batch, `ProjectMemoryLinter` performs a read-only whole-wiki check for traceability, revision consistency, exact and likely semantic duplicates, link integrity, and connectedness.

Only one compilation runs at a time through the existing `GemmaExecutionGate`. While the app remains foregrounded, it automatically drains the queue sequentially and refreshes the Wiki after every memory. There is no routine review inbox or “compile next” work for the user; manual interaction remains only as an exceptional retry for a failed model run. Cancellation safely returns the current source to the local queue.

### Additive database schema

| Table | Purpose |
| --- | --- |
| `wikiPage` | Current typed page, normalized identity, aliases, summary, and revision number |
| `wikiEvidence` | Many-to-many provenance between a page and immutable source memories, including how the source affected the page |
| `wikiPageLink` | Canonically ordered, de-duplicated page connections used for navigation and candidate expansion |
| `wikiRevision` | Append-only before/after summary, effect, rationale, source memory, model version, and timestamp |
| `wikiCompilation` | Idempotent per-memory queue state tied to the source memory's last update |
| `wikiPageSearchIndex` | Page search text, source timestamp, BGE Micro vector, and embedding-model identifier |
| `projectMemoryRun` | Append-only compiler/lint operation with source, result, model/prompt/program versions, counts, and acceptance rationale |
| `projectMemoryCheck` | Deterministic check result and severity for one operation |

All tables are separate from the v1 memory and search tables. Foreign keys clean up source links if a memory is explicitly deleted, while page revision history remains browsable where possible.

### Model safety boundary

Gemma proposes a bounded patch; it never writes SQLite directly. Deterministic code enforces:

- the versioned project-specific page schema;
- maximum lengths and page/update counts;
- candidate UUID allowlisting;
- normalized type-and-title uniqueness;
- de-duplicated aliases and links;
- source-memory provenance for every revision;
- rejection and automatic re-queue when the source changes during a long model run;
- transactional all-or-nothing application.

A contradiction is retained as a `contradicted` revision and evidence effect rather than silently overwriting history. The page detail screen exposes the current synthesis, aliases, related pages, cited source memories, revision numbers, rationales, and before/after summaries.

The user-facing Wiki UI keeps compiler terminology behind an optional **How Project Memory works** sheet. It exposes the program objective and schema, while page details present the current synthesis first, rename evidence to **Sources**, translate internal effects into plain language, and hide the History section until a page has more than one revision. Contradictions remain visible as information, but normal routing, page selection, linking, and updates are automatic rather than assigned to a human review workflow.

### Hybrid candidate retrieval

`~/models/bge-micro-v2` is referenced as an Xcode folder resource, just like the development Gemma bundle. `MLXTextEmbeddingService` loads it only from the app bundle; it has no downloader or remote-model fallback. Memory and wiki vectors are normalized, encoded as Float32 data, and invalidated by both content timestamps and model identifier.

For wiki compilation, semantic similarity can introduce a candidate even when a new memory paraphrases the page completely. Exact names and aliases still receive strong lexical weight, and the top direct matches still expand through one page-graph hop. Deterministic code applies thresholds and caps the result at eight before Gemma sees it. This substantially narrows duplicate-page risk without asking Gemma to inspect the entire wiki.

BGE Micro is English-focused. Its small size is the right fit for the current English prototype and iPhone memory ceiling; multilingual retrieval remains a future model-quality decision rather than an implicit claim.

### Private Project Memory program

`ProjectMemoryProgram` is a fixed, versioned policy boundary rather than an unbounded agent prompt. Version `private-project-memory-v1` states the objective and exposes eight page types in both the compiler prompt and product UI: project, decision, constraint, experiment, feedback, person, open question, and reference knowledge. The compiler prompt is independently versioned as `project-memory-compiler-v6`.

The v6 boundary asks for no more than three concise, distinct pages, explicitly distinguishes active projects from rules and requirements, and requires complete closing delimiters. The parser extracts balanced JSON objects while respecting quoted braces and escapes, so Markdown fences or surrounding prose cannot corrupt an otherwise valid object. If the first output cannot be decoded, the same local Gemma session receives a stricter one-page repair instruction with the literal schema and enum values. If that repair is still malformed, a deterministic recovery may attach the source to exactly one strong retrieved candidate while preserving that page's existing title and synthesis byte-for-byte; without a strong candidate it records an explicit, audited no-change result. Recovered no-change rows and failed rows from an older compiler version are requeued once automatically after an upgrade. Candidate allowlisting, a conservative score boundary, field bounds, patch checks, and transactional persistence still control every mutation; raw malformed output is never logged or persisted.

This schema makes the product opinionated about project continuity while remaining broad enough for founders, makers, and creative work. The legacy `concept` database value remains valid and is presented as Reference Knowledge, so existing installs migrate without rewriting pages.

### Project Story, Knowledge Map, Audit, and protected evaluation

Every new compilation starts an append-only `projectMemoryRun`. The record identifies the source memory, operation, timestamps, Gemma/model version, prompt version, program version, proposed and accepted page counts, final keep/discard state, and a bounded rationale. Accepted `wikiRevision` rows link back to the run. `projectMemoryCheck` rows store named deterministic outcomes with information, warning, or blocking severity.

The protected patch evaluator checks the three-page budget, retrieved-candidate boundary, required source-grounded fields, unique targets, and self-link hygiene. It also applies a conservative type-suitability filter and token-overlap similarity gate. A likely equivalent new page is rewritten as an update to a retrieved canonical candidate; equivalent proposals inside one patch are collapsed. A blocking failure converts the proposed patch to an empty patch before persistence. An empty but safe Gemma proposal is also recorded as **No change**, which prevents needless pages without creating manual review work.

After at least one memory is processed in a foreground compilation batch, the read-only linter checks the whole graph. Its connectedness result is informational because separate projects can legitimately form separate components; traceability, revision consistency, exact uniqueness, likely semantic uniqueness, and link integrity are stronger structural signals.

The user-facing surface has three modes. **Story** narrates saved-memory-to-page changes and translates failures or no-change runs into plain language. **Map** is a tappable flowchart: solid lines are persisted page links and dotted lines are relationships derived from shared source evidence; an equivalent textual connection list keeps the graph accessible. **Audit** retains the chronological technical log, original source navigation, accepted before/after patches, check results, and reproducibility identifiers. It stores operational evidence and rationale, not chain-of-thought.

`RememberTests` contains a fixed deterministic quality benchmark covering valid decision/constraint classification, rejection of submission rules misclassified as a project, consolidation into an existing differently titled submission page, and whole-wiki likely-duplicate detection. This measures the protected quality layer without requiring Gemma or device hardware; model-output replay remains a separate physical-device evaluation concern.

Runs that were in progress when the process stopped are marked failed on the next bootstrap. Existing wiki revisions have a null run identifier and remain valid; they naturally predate the Research History migration.

### Open Markdown projection

`ProjectMemoryMarkdownRenderer` produces a deterministic, dependency-free text projection and `ProjectMemoryExportDocument` presents it through SwiftUI's system file exporter. The document includes YAML metadata, schema-grouped index, pages, aliases, connections, source-memory identifiers and titles, revision history, model/prompt/program versions, checks, and the chronological operation ledger.

This is an explicit export initiated from the Project Memory menu. It does not embed source binaries, copy the SQLite database, or change the private vault. The format is therefore portable and inspectable but is not yet the PRD's complete backup/delete-all solution.

### Living Wiki physical-device acceptance test

1. Run the **Remember** scheme on the physical iPhone.
2. Open **Privacy → App experience** and confirm **Project Memory** is enabled.
3. Open the Project tab. Existing analyzed memories appear briefly in the compiler backlog and Remember automatically processes them one at a time without a compile button.
4. Keep the app foregrounded during compilation. Open a generated page and verify its type, summary, source memory, and current synthesis.
5. Save another memory about the same project or concept, return to Remember, and let both normal analysis and wiki compilation finish.
6. Reopen the page and confirm the revision number increased, the second source is cited, and **See what changed** shows the previous and current synthesis.
7. If the second source conflicts, verify the page shows **Contradiction found** rather than silently erasing the earlier state.
8. Turn off Project Memory from the Memories ellipsis menu. Confirm the Project tab disappears and all v1 features still work.
9. Re-enable it from the same menu and confirm the pages and history return.
10. Ask a question represented by a wiki page. Verify the response is organized from the compiled page but its visible citations open original memories, not the derived wiki page.
11. Open **Project → Open Project Story**. Verify **Story** shows the newest source-to-page flow in plain language.
12. Open **Map**, tap a page node, and verify solid explicit links, dotted shared-source relationships, and the accessible Connections list where applicable.
13. Open **Audit**. Verify the newest integration shows its source, kept/no-change result, checks, model/prompt/program versions, and accepted patch details. Run **Check project memory quality** from Story and confirm a new read-only health-check chapter appears.
14. Choose **Export open Markdown**, save the document in Files, and inspect its index, pages, sources, revisions, and Research History section.
