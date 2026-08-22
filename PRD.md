# Product Requirements Document
## [Working Title] — On-Device Private Memory for iPhone

---

## 1. Overview

A private, fully on-device "second brain" app for iPhone. Users save screenshots, links, photos, and voice notes into the app via the iOS Share Sheet or in-app capture. A local AI model (Gemma 4 E2B) runs entirely on-device to caption, transcribe, tag, and index everything, making it searchable in plain language later — with a verifiable guarantee that no content ever leaves the phone.

---

## 2. Problem

- **Siri AI (iOS 27)** now searches Messages/Photos/Mail for personal context, but relies on Apple's cloud fallback (Private Cloud Compute) and requires trusting Apple's architecture end-to-end.
- **OpenClaw-style agents** solve "private AI" by requiring users to host and secure their own gateway server — powerful but heavy, technical, and carries real prompt-injection/attack-surface risk.
- **Nothing's Essential Space** is the closest existing product to this idea and validates the concept (see §3), but it processes content via cloud AI, is moving toward cloud sync, is monetizing via metered "AI credits," and is locked to Nothing hardware.
- **Gap:** no simple, free, verifiably-offline tool exists for "save things I care about, find them later in plain language" on iPhone.

---

## 3. Competitive Context

| | Siri AI | OpenClaw | Essential Space | This app |
|---|---|---|---|---|
| Where inference runs | On-device + Apple cloud (PCC) | Self-hosted gateway (Mac/PC/server) | Cloud (metered AI credits) | 100% on-device (E2B) |
| Data access | System-level (Messages, Mail, Photos) | Whatever you grant the gateway | Only what you explicitly capture | Only what you explicitly capture |
| Setup | None (built into OS) | Server setup, gateway pairing | None (built into OS) | Install and go |
| Cost | Free w/ Apple Intelligence | Free (OSS) + your own compute/API costs | Free trial → subscription (~$120/yr) | Free, no subscription |
| Platform | Apple only | Cross-platform | Nothing phones only | iPhone (portable concept) |
| Network calls | Yes (cloud fallback) | Yes (gateway, often cloud LLM) | Yes | **Zero, ever** |

**Positioning:** "Essential Space, but the memory never leaves your pocket — no proprietary hardware, no subscription, no server to run."

---

## 4. Capabilities

### 4.1 Capture (input)
- iOS Share Extension: accepts screenshots, links, photos, selected text, PDFs from any app
- In-app quick capture: voice memo (on-device transcription), typed note, camera photo
- Stretch: clipboard watcher prompting "save this?"

### 4.2 Processing (on-device, via Gemma E2B)
- Vision captioning + OCR on images/screenshots
- Voice memo transcription + summarization
- Entity/tag extraction (dates, places, names, categories)
- Auto-generated title + one-line summary per item

### 4.3 Retrieval
- Natural-language semantic search ("that restaurant my friend sent me")
- Filter by type / date range / tag
- Optional proactive resurfacing (e.g., "saved 3 weeks ago, never opened")

### 4.4 Trust / transparency layer (core differentiator — do not cut from v1)
- Persistent, always-visible network-activity indicator (literal proof of zero outbound connections)
- Local, on-device AI usage log the user can inspect
- Full local export and delete, no account or login required

---

## 5. App Shape

- **Share Extension** — primary entry point for captured content
- **Main app**: reverse-chronological feed (auto-tagged) + search bar as primary UI
- **Item detail view**: original content + editable AI summary/tags (AI will be wrong sometimes — must be correctable)
- **Background processing queue**: captures feel instant; summarization happens asynchronously

---

## 6. Technical Architecture

### 6.1 Data flow
1. User shares content → Share Extension writes raw item to a shared **App Group** container (fast, minimal memory, no inference here)
2. Extension exits immediately (must stay under iOS's strict Share Extension memory ceiling, historically ~120MB — cannot run model inference inside the extension)
3. Main app, when foregrounded (or during a background execution window), picks up unprocessed items from the App Group container
4. Main app runs Gemma E2B inference: captioning/OCR/transcription/tagging/summarization
5. Results + embeddings written to local SQLite store
6. Search queries embedded the same way, compared via local vector similarity (brute-force cosine is sufficient at phone-realistic scale — thousands to tens of thousands of items)

### 6.2 Why processing can't happen in the Share Extension
This is the single most important constraint in the whole architecture. Gemma E2B at 4-bit quantization needs roughly 1–3GB RAM to load and run. iOS Share Extensions are killed by the OS well before that. This is not a design choice — it is an OS-enforced hard limit. It means:
- Capture must always be a two-step process: fast raw save, then deferred processing
- A visible "analyzing…" state is required (this mirrors Essential Space's own UI, for the same underlying OS reason)
- The app needs a clear state machine: `captured` → `processing` → `indexed`

---

## 7. Model Acquisition & Integration (Gemma 4 E2B)

### 7.1 Important: the Edge Gallery download does not transfer
The model downloaded inside Google's **AI Edge Gallery** app lives inside that app's sandboxed container. iOS sandboxing prevents any other app — including yours — from accessing it. You must acquire the model weights again, in the format required by whichever runtime you choose below. Edge Gallery uses the LiteRT (`.litertlm`/`.task`) format specifically for its own use.

### 7.2 Choose one runtime path

**Option A — MLX Swift (recommended starting point)**
- Best native Swift developer experience; strong community momentum for Gemma 4 on iPhone
- Model source: `mlx-community/gemma-4-e2b-it-4bit` on Hugging Face (pre-converted, ready to use)
- Integration: `mlx-swift` + `mlx-swift-lm` (or an mlx-vlm-equivalent Swift port if vision is needed)
- Runs on GPU via Metal, not the Neural Engine
- Benchmarked community results: ~6s warm load, ~340–390MB RAM after load, 12–14 tok/s on iPhone

**Option B — CoreML-LLM (best power/efficiency, text-only currently)**
- Uses the Neural Engine directly — dramatically lower power draw (~2W) than GPU-based approaches
- Fastest and most efficient of the three options for text
- Limitation as of writing: text-only for E2B (no multimodal/vision support yet in this framework) — a blocker if OCR/image captioning is core to v1, unless paired with a separate on-device OCR pass (e.g., Apple's own Vision framework) to compensate
- Model must be converted to `.mlpackage`/`.mlmodelc` via the project's bundle-builder scripts

**Option C — LiteRT / MediaPipe (Google's official cross-platform path)**
- Same underlying format as Edge Gallery, so most "proven to work" out of the box
- Better for future Android portability if that's ever a goal
- Historically an extra translation layer on iOS (LiteRT → Metal) vs. Apple's own frameworks, per community reports
- Model source: `litert-community/gemma-4-E2B-it-litert-lm` on Hugging Face

### 7.3 Recommendation for v1
Start with **MLX Swift**, since it natively supports both vision and text (needed for screenshot/photo captioning), has the most active Swift tooling community for Gemma 4 specifically, and has real, favorable on-device benchmarks already reported. Revisit CoreML-LLM once/if it adds multimodal support, since its power efficiency is meaningfully better for an app meant to run inference many times a day.

### 7.4 Delivery: bundle vs. download-on-first-launch
E2B is roughly 1.3–2.5GB depending on quantization — too large to comfortably bundle inside the app binary for App Store distribution (App Store has size/cellular-download thresholds that affect UX). Recommended: download the model from Hugging Face (or your own CDN mirror) on first launch, store it in the app's local container, and show a one-time setup/progress screen. For your own dev-only sideloaded testing, bundling directly is simplest and fine.

---

## 8. Feasibility Assessment

**Low risk / well-established:**
- Running E2B on-device via MLX Swift or CoreML-LLM (proven, benchmarked by the community)
- Local vector search at phone-realistic data volumes (brute-force is fine; no need for a dedicated vector DB)
- Local storage (SQLite)

**Moderate risk / requires careful engineering:**
- Share Extension memory ceiling forcing a two-phase capture/process flow (see §6.2) — architectural, not exotic, but easy to get wrong on a first pass
- Background execution windows are short and not guaranteed by iOS — processing timing needs a robust queue, not an assumption that items process instantly
- Battery/thermal management if processing batches are large — mitigate by processing on app-open rather than attempting continuous background inference

**Highest-effort, ongoing risk (not a one-time build problem):**
- **Retrieval quality.** Indexing itself (embeddings + similarity search) is mechanically simple. Making search actually *feel* smart — correctly resolving a vague query like "that restaurant thing" weeks later — depends entirely on caption/tag quality from a 2B-parameter model on noisy, OCR-heavy screenshots, plus embedding/ranking tuning. This is where most iteration time will go, and it's the difference between the app feeling magic vs. feeling like a junk drawer with a search bar.

**Bottom line:** the hardest part is *not* indexing — indexing is the easy, well-trodden part of this stack. The hardest parts are (1) the iOS execution-model plumbing around the Share Extension's memory ceiling, and (2) the softer, ongoing problem of retrieval quality with a small model on messy real-world input.

---

## 9. Roadmap

**v1 (MVP)**
- Share Extension capture (screenshots, links, photos, text)
- Async processing queue with visible state (captured → analyzing → indexed)
- Vision captioning/OCR + tagging via Gemma E2B (MLX Swift)
- Feed view + natural-language search
- Editable AI summaries/tags
- Network-activity indicator (trust layer)

**v2**
- Voice memo capture + transcription
- Proactive resurfacing / reminders
- Collections/tags UI
- Export/delete tooling

**Explicitly out of scope (see earlier discussion)**
- Reading Messages, Notes, or other apps' data — not technically accessible to third-party apps, and deliberately not the product shape (opt-in capture, not passive phone-wide indexing)
- Agentic actions (booking, sending messages) — this is a memory tool, not an agent, by design

---

## 10. Open Questions
- Vision support timeline for CoreML-LLM — revisit runtime choice if/when it lands
- Whether to mirror model weights on your own CDN vs. relying on Hugging Face directly for first-launch download reliability
- Minimum supported iPhone (RAM floor — likely iPhone 15 Pro / 8GB+ devices only, matching community-reported E2B requirements)
