# Remember reset implementation

## Runtime flow

1. The app or Share Extension writes a captured source into the local vault.
2. The main app extracts bounded source content. Apple Vision handles image/PDF OCR and image labels; Apple Speech handles voice transcription.
3. `OpenAIMemoryAnalyzer` sends the relevant content through the configured proxy and requests schema-constrained metadata from the OpenAI Responses API.
4. `OpenAITextEmbeddingService` obtains embeddings from the proxy and stores normalized vectors alongside local search records.
5. Exact local search remains immediate. AI-assisted search may expand the query and combine lexical results with OpenAI embedding similarity.
6. Ask Remember retrieves a bounded set of chunks, requests claim/evidence pairs, and accepts a generated claim only when its quoted evidence occurs literally in the selected source. Otherwise it returns source-only results.

The live dependency graph is assembled in `MemoryPipeline.live()`. It creates one `OpenAIAPIClient` shared by analysis, embeddings, query expansion, and Ask.

## OpenAI boundary

`OpenAIAPI.swift` sends requests only to `REMEMBER_OPENAI_BASE_URL`, defaulting to the local development proxy. It has no API-key field. Responses requests use structured JSON schemas and `store: false`; embedding requests use the dedicated embedding model.

`server/openai_proxy.py`:

- loads configuration from the ignored root `.env`;
- exposes `/health`, `/v1/responses`, and `/v1/embeddings`;
- injects `OPENAI_API_KEY` and enforces server-configured model identifiers;
- accepts JSON objects only and caps bodies at 40 MiB;
- applies an upstream timeout;
- avoids logging payloads and credentials.

It is a development component, not a production edge service. Production work must add caller authentication, TLS, rate limiting, request ownership controls, and managed secrets.

## Failure behavior

OpenAI transport, configuration, rate-limit, refusal, context-window, and response-decoding failures are converted to bounded product errors. Memory analysis can fall back to deterministic metadata derived from extracted source content. Search retains exact matching, and Ask can return retrieved source excerpts without a generated answer.

## Project reset

The Project tab now renders `ProjectView`, a single placeholder announcing the rebuild. Former Project Story, Knowledge Map, Research History, search, compilation, review, and Markdown-export UI/code paths were removed.

Some legacy Project persistence structures remain in `LivingWiki.swift`, `ProjectMemory.swift`, and `MemoryStore`. They are intentionally dormant and preserve schema compatibility with existing SQLite databases. Removing those tables or records would be a separate data migration requiring an explicit retention decision; this reset neither reads them into the UI nor writes new Project results.

## Removed local-model stack

The target no longer links MLX, MLXLM, MLXVLM, MLXEmbedders, Hugging Face, Tokenizers, or local-model resources. Gemma/LFM analyzers, assistants, bundle loaders, tokenizer loaders, embedding loaders, scripts, device runners, and result files were removed. Downloaded Gemma, LFM, and BGE model directories were deleted from the development machine.

Internal names such as `LocalAIActivity` remain for database compatibility. They describe persisted activity records, not a local-model runtime.

## Configuration

`.env.example` defines:

- `OPENAI_API_KEY`
- `OPENAI_MODEL=gpt-5.5`
- `OPENAI_EMBEDDING_MODEL=text-embedding-3-small`
- `OPENAI_PROXY_HOST=127.0.0.1`
- `OPENAI_PROXY_PORT=8787`

The real `.env` is ignored. The requested generation identifier is configurable because model access is account-dependent; the implementation does not silently replace it.

## Verification strategy

- Compile the Python proxy and check `/health` with an empty key.
- Resolve the Xcode project and confirm only the database package remains.
- Build the app and test bundle for an iOS simulator.
- Run deterministic unit tests without contacting OpenAI.
- With a user-supplied key, separately validate API-backed analysis, embeddings, image input, and grounded Ask against the account's available `gpt-5.5` model.
