# Remember

Remember is an iPhone memory vault for notes, images, links, PDFs, and voice recordings. This repository is currently at a reset baseline: **Memories** and **Settings** remain active, while **Project** is intentionally reduced to a placeholder ahead of a full redesign.

## Current product surface

- Capture content in the app or through the Share Extension.
- Keep original files and metadata in the local vault.
- Extract text with Apple Vision and transcribe speech with Apple Speech on-device.
- Use OpenAI for titles, summaries, tags, embeddings, query expansion, and grounded answers.
- Verify generated answer quotes against retrieved source text before displaying them.
- Browse, search, edit, organize, and delete saved memories.
- Open the Project tab to see the rebuild placeholder. The former Project Story, Knowledge Map, compilation, review, audit, and export interfaces are no longer active.

No Gemma, LFM, BGE, MLX, Hugging Face, or other downloaded model weights are required or bundled.

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

The iOS app does not contain the OpenAI key. It sends bounded requests to the configured proxy, which authenticates upstream to OpenAI. Depending on the operation, those requests can contain:

- extracted text and user captions for memory analysis;
- an image being analyzed;
- memory chunks or a search query for embeddings;
- selected source excerpts and a question for Ask Remember.

Original vault files, the SQLite database, and local activity metadata stay on the device unless their content is included in one of those explicit AI requests. The app sets `store: false` on Responses API requests. This architecture is appropriate for development; production deployment still needs authenticated client-to-proxy access, rate limiting, abuse controls, and a published privacy policy.

## Architecture

- `Remember/Remember/` — SwiftUI app, capture pipeline, local vault, extraction, search, OpenAI client, and reset Project screen.
- `Remember/RememberShareExtension/` — lightweight capture handoff; it does not call OpenAI.
- `server/openai_proxy.py` — development proxy that loads `.env`, injects the API key, and forwards only Responses and Embeddings requests.
- `Evaluation/` and `scripts/` — provider-independent grounded-answer fixtures and deterministic scoring utilities.

Legacy Project database records and compatibility types remain dormant so existing local databases are not destructively migrated during this reset. No live navigation or pipeline invokes the former Project compiler.

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
