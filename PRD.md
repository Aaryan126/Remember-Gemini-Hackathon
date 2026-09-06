# Remember product reset brief

## Status

This document defines the baseline before the Project experience is redesigned. It intentionally replaces the previous Gemma/on-device-LLM and Project Story/Map specification.

## Product promise

Remember helps a user deliberately save personal source material, find it later, and ask grounded questions about it. Saved originals remain authoritative and locally manageable. AI assistance is transparent about its OpenAI data boundary and must never fabricate a source citation.

## Active scope

### Memories

- Capture notes, images, links, PDFs, and voice recordings.
- Accept Share Extension imports without loading an AI model in the extension.
- Store originals and metadata in the local app vault.
- Use Apple system frameworks for OCR, image labels, and speech transcription.
- Use the configured OpenAI service for semantic embeddings and generative analysis.
- Support browsing, exact and semantic search, filters, editing, collections, tags, retry, and deletion.
- Answer questions from a bounded set of retrieved excerpts. Every displayed evidence quote must be a literal substring of its source.
- Degrade to deterministic metadata and source-only results when OpenAI is unavailable.

### Settings

- Preserve the existing settings structure except where old Project controls or inaccurate local-only privacy claims must be removed.
- Show an honest privacy boundary and content-free AI activity records.

### Project

- Show only a neutral rebuild placeholder.
- Do not compile, mutate, summarize, map, narrate, export, or review Project knowledge.
- Do not define the replacement information architecture in this reset.
- Preserve dormant legacy persistence records temporarily to avoid destructive migration of existing user databases.

## AI architecture

- All required hosted generation uses the OpenAI Responses API with the requested `gpt-5.5` model identifier.
- Semantic vectors use the OpenAI Embeddings API with `text-embedding-3-small`.
- The iOS client talks to a small server-side proxy and never stores an OpenAI secret.
- Configuration is provided through an ignored `.env`; `.env.example` contains sanitized placeholders.
- The app does not bundle, download, or load Gemma, LFM, BGE, MLX, Hugging Face, Tokenizers, or other open-source model weights.
- There is no automatic substitution of a different generation model. Unsupported model access must produce a clear failure.

## Privacy and security requirements

- Never place the OpenAI key in the app binary, UI, logs, fixtures, or repository.
- Bound request sizes and validate responses at both proxy and app boundaries.
- Never log prompts, source excerpts, images, transcripts, or credentials.
- Explain that relevant content leaves the device for OpenAI processing.
- Keep Share Extension capture, vault storage, Apple OCR, and Apple speech transcription local.
- A production proxy must add authenticated app access, rate limiting, monitoring without sensitive payloads, and operational secret management.

## Out of scope for this reset

- The redesigned Project concept, schema, navigation, story, or map.
- Cloud sync, accounts, collaboration, background guarantees, and complete backup/export.
- A production deployment of the included development proxy.
- Reintroducing any local language or embedding model.

## Acceptance criteria

- The app and test target build without model-framework packages or model resources.
- No active code path references the former local LLMs or Project compiler.
- Project navigation opens only the rebuild placeholder.
- Memories and Settings remain usable, with copy updated for the OpenAI boundary.
- `.env` is ignored and `.env.example` documents every required variable.
- The proxy health endpoint works without exposing a secret.
- Old downloaded model directories are removed from the development machine.
