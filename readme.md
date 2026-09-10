# Remember

Remember is an iPhone memory vault for notes, images, videos, links, PDFs, and voice recordings. **Memories** handles capture and retrieval; **Project** shows the provenance timeline, topic graph, and each thread’s River; **Settings** includes optional cloud assistance and the archive.

## Current product surface

- Capture content in the app or through the Share Extension.
- Keep original files and metadata in the local vault.
- Import photos or videos through the system Photos picker, preview, add a caption, and save. Video imports also work from Files. Native inline video controls support playback and scrubbing; playback is user-initiated and pauses on leaving/backgrounding. Videos are stored locally; only captions are indexed, not scenes or video speech. Photos-picker iCloud downloads require connectivity.
- Extract text with Apple Vision and transcribe speech with Apple Speech on-device.
- Enrich captures locally with Apple extraction and Foundation Models where available; organize topics using contextual and sentence embeddings plus shared source evidence.
- Opt into OpenAI capture enrichment and topic reasoning, or explicitly use AI search and grounded answers.
- Verify generated answer quotes against retrieved source text before displaying them.
- Browse, search, revise, organize, archive, and restore saved memories without erasing their history.
- Switch Project between Timeline and Graph, drill into a topic’s River, inspect placement evidence, compare past state, and correct organization. High-confidence merges are automatic; splits require acceptance.
- Graph dedicates its available height to the memory map, with title-only circles sized by each thread’s memory count and shared-source/tag connections. Drag to explore at a readable browsing scale; pinch and zoom buttons are intentionally absent. Recenter returns to the starting position. Timeline contains the complete All threads list with full, Dynamic Type titles, plus source/date/topic filters and activity history. Tapping either a circle or a list row opens the same River directly, with photos, videos, voice players, and notes in chronological capture/revision entries—not a separate Sources section. Media taps open Memory, and Back returns straight to the River.
- The map uses a fixed center-out honeycomb with the largest thread initially at its center. Dragging translates the whole grid under your finger; releasing smoothly snaps the nearest occupied slot into the fixed center. Short drags return to the current node, and empty slots are never snap targets. A size-only magnifying lens brings central circles forward and shrinks peripheral ones without bending rows or displacing neighbors. Slots reserve enough room for focus magnification. Near-monochrome frosted surfaces use silver-gray rims and soft blue-white highlights. Touch/drag focuses a circle; hold to reveal a compact preview with its full title, memory count, related-thread count, and tags. A quick tap still enters the River directly with Apple's native zoom transition. Clear focus or tap the background to dismiss the preview. Reduce Motion settles immediately and disables magnification, lift, and zoom transitions while retaining connection highlighting; Reduce Transparency uses opaque surfaces.
- Thread history’s vertical ellipsis menu offers Edit thread and Delete thread. Deleting archives only the thread, preserving its memories and other memberships; restore it from Settings → Archive.
- Map node surfaces use satin graphite in Dark Mode and soft neutrals in Light Mode, with a restrained cool-silver rim reflection that follows the grid's movement. Center/focus brightness provides hierarchy without arbitrary topic colors. There is no idle shimmer, outer glow, extra timer, or motion-sensor input; Reduce Motion fixes the lighting direction and Increased Contrast strengthens the outline.
- Map circles use compact, whole-word display labels with a uniform font size per label. A fixed-height caption below the map heading shows the centered thread's full title after settling; unusually long captions can scroll without moving the grid. Original titles, River navigation, and VoiceOver labels are unchanged. Labels are derived locally with conservative word-selection rules, without model/network calls or saved renames.
- The River has one continuous left-hand branch running beside the full height of its entries. Media and text share a column to its right; junctions mark each event without breaking the main line.
- Opening the capture dial blurs and de-emphasizes the library. Rotate directly around its centre; a flick coasts in the same direction and gradually slows. Dragging again, selecting a capture, or dismissing the menu cancels momentum. Reduce Motion disables coasting, and Reduce Transparency is respected. The add button appears only at the library root, not on memory details.

Dial momentum uses elapsed display-link time and opts into faster ProMotion refresh rates while animating; iOS still controls the actual refresh rate according to device and power conditions. See [Apple’s ProMotion guidance](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays).

No third-party model weights are bundled. Apple contextual embedding assets may download on demand; capture and singleton topics remain available while models are unavailable.

Automatic organization requires agreement between both embedding signals, individual-member checks, and specific shared source terms. Ambiguous matches remain separate or use bounded reasoning. Existing mistaken groups receive reviewable split suggestions rather than being silently rewritten. See the [device evaluation and clustering policy](docs/evaluations/2026-09-07-grounded-clustering.md) and [repeatable device-test instructions](scripts/embedding-evaluation/README.md).

## OpenAI setup

The API key belongs in the development proxy, never in the iOS app or source control.

1. Copy `.env.example` to `.env`.
2. Add a project-scoped key as `OPENAI_API_KEY`.
3. Start the proxy:

   ```bash
   python3 server/openai_proxy.py
   ```

4. Open `Remember/Remember.xcodeproj` and run the `Remember` scheme.

The default simulator endpoint is `http://127.0.0.1:8787/v1`. Override it with the `REMEMBER_OPENAI_BASE_URL` scheme environment variable when the app needs a different proxy URL. A physical iPhone cannot reach the Mac through its own `127.0.0.1`; use a secured, reachable proxy endpoint for device testing.

The requested generation model is `gpt-5.5`, configured through `OPENAI_MODEL`. Embeddings use `text-embedding-3-small` through `OPENAI_EMBEDDING_MODEL`. The proxy enforces these server-side values so the client cannot select arbitrary upstream models. There is no silent fallback to another hosted model.

## Data boundary

The iOS app does not contain the OpenAI key. Cloud assistance is off by default. Explicit Ask and AI-search actions remain cloud features independently of that setting. Bounded requests go to the configured proxy, which authenticates upstream to OpenAI. Depending on the enabled operation, requests can contain:

- extracted text and user captions for memory analysis;
- an image being analyzed;
- memory chunks or a search query for embeddings;
- selected source excerpts and a question for Ask Remember.

Original vault files, the SQLite database, and local activity metadata stay on the device unless their content is included in one of those explicit AI requests. The app sets `store: false` on Responses API requests. This architecture is appropriate for development; production deployment still needs authenticated client-to-proxy access, rate limiting, abuse controls, and a published privacy policy.

## Architecture

- `Remember/Remember/` — SwiftUI app, capture pipeline, local vault, extraction, search, optional OpenAI client, append-only provenance, and Project views.
- `Remember/RememberShareExtension/` — lightweight capture handoff; it does not call OpenAI.
- `server/openai_proxy.py` — development proxy that loads `.env`, injects the API key, and forwards only Responses and Embeddings requests.
- `Evaluation/` and `scripts/` — provider-independent grounded-answer fixtures and deterministic scoring utilities.

Legacy Project database records and compatibility types remain dormant so existing local databases are not destructively migrated during this reset. No live navigation or pipeline invokes the former Project compiler.

The new provenance layer is independent of those legacy records. See [Provenance architecture and operation](docs/provenance.md) for migration, retention, organization policies, and validation details.

## Validation

Useful local checks:

```bash
python3 -m py_compile server/openai_proxy.py
xcodebuild -project Remember/Remember.xcodeproj -scheme Remember \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath /tmp/RememberOpenAIReset CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Remember/Remember.xcodeproj -scheme Remember \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath /tmp/RememberOpenAIReset CODE_SIGNING_ALLOWED=NO build-for-testing
```

API-backed behavior requires a valid key and access to the configured `gpt-5.5` model. Deterministic fallbacks keep capture and source-only retrieval useful when the proxy is unavailable.

For UI checks on a personal iPhone, select only `testDialFollowsDragInBothDirections`, `testDialFlingCanBeDismissedAndReopened`, `testCaptureButtonIsHiddenOnMemoryDetail`, `testRadialCaptureMenuExposesEveryCaptureAction`, `testExistingLibraryGraphNavigationWithoutCaptures`, and `testExistingMapFocusHoldDragAndReturn` in `RememberUITests`. The detail and graph checks require existing memories/threads, and the graph checks restore the previous Timeline/Graph selection. These checks do not create or archive captures; other UI tests seed sample memories and belong on a simulator or disposable test device. Keep the phone unlocked and untouched during automation.
