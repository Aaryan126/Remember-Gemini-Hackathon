# Provenance & timeline layer — feature spec

## Overview

The core differentiator of the app isn't "AI auto-organizes your stuff" — that's now table stakes (mymind and others already do it). The differentiator is treating every piece of captured content as part of a **traceable, versioned history** — a "git for your mind." Every note, photo, or voice memo is a commit; the app never just shows you a tidy current state, it can always show you *how that state came to be*.

This document breaks the feature into its architectural layers, explains what each does and why, maps the git analogy explicitly, and lists the user-facing outcomes this is meant to produce.

---

## Core concept

Instead of "save item → file it into a bucket," the model is:

**Capture → immutable commit → automatic enrichment → graph placement → user-facing timeline/graph**

Nothing is ever silently overwritten. Corrections and re-organizations are new events layered on top of history, not edits to it. This is what makes the "git" comparison literal rather than just a metaphor.

---

## The five layers

### 1. Capture layer
**What it does:** entry point for notes, photos, voice memos, screenshots. Accepts content and passes it downstream unmodified — no processing happens here.

**Why:** keeps capture instant. The app should never introduce latency at the moment of adding something; that would undermine the "frictionless mind-dump" premise the whole app is built on.

### 2. Ledger layer
**What it does:** every captured item becomes an immutable **commit** — raw content plus metadata (timestamp, source type, device context). Commits are never edited or deleted, only appended to or marked as superseded.

**Why:** this is what actually earns the "git" comparison and makes user trust possible. If commits could be silently rewritten, the audit trail — the core differentiator — would be worthless. Immutability also gives near-free undo/revert: fixing a mistake later is a new commit, not a destructive edit.

### 3. Enrichment layer
**What it does:** runs extraction on each commit — Vision framework for images (object/scene labels, embeddings/feature prints), NaturalLanguage/OCR for text — producing tags, entities, and similarity vectors. This is also where Apple's Foundation Models framework plugs in: structured tagging today, richer multimodal captioning once broadly available (iOS 27+).

**Why:** separating enrichment from the ledger means the tagging/model layer can be improved or swapped later without touching historical data — old commits get silently re-enriched rather than needing migration. It also means enrichment can fail, be slow, or run in the background without blocking capture.

### 4. Graph layer
**What it does:** takes enrichment output and decides placement — which cluster a commit joins, what it links to, whether two separate threads should merge. Owns "branches" (parallel contexts like Work vs. a specific class) and visible merge events when threads turn out to be related.

**Why:** this is the layer users actually *feel* as the magic — automatic organizing without folders. Making it a distinct layer (rather than folding clustering logic into enrichment) is what makes placement decisions themselves loggable — which is what powers blame/traceability downstream.

**How placement actually works (this is the hardest layer to build):**

The core mechanism runs on embeddings + similarity math, not the LLM — the LLM is reserved for hard cases, which keeps the "magic" clustering identical in free and premium tiers.

1. **Unify into one embedding space.** Convert everything to text first — notes as-is, voice as transcripts, images via Vision-generated captions/labels/OCR — then embed with Apple's `NLContextualEmbedding` (on-device, zero bundle size, available since iOS 17, so no version-gating concern). This makes a note, a transcript, and a captioned photo directly comparable.
2. **Real-time placement via nearest-centroid comparison.** New commit's embedding is compared (cosine similarity) against existing cluster centroids. A clear winner above a threshold → placed immediately, no LLM involved.
3. **Close calls get escalated, not guessed.** When the top two candidate clusters are nearly tied, that's a narrow, well-scoped judgment call — hand the item plus short summaries of the 1-2 candidates to an LLM to decide (or assign to both).
4. **A periodic batch pass catches what real-time placement misses.** Real-time thresholding only looks at existing centroids, not the whole graph. A nightly (or every-N-commits) re-clustering pass over the full embedding set catches clusters that should merge, or ones that have grown broad enough to split — this is what produces the visible **merge events** described in the git-concept mapping below.

**Free vs. premium split for this layer:**

The free tier should do real organizing, not a crippled demo — premium upgrades the *reasoning*, not the core promise, which keeps the privacy claim honest for every user.

| | Free | Premium |
|---|---|---|
| Embeddings + real-time placement | On-device (`NLContextualEmbedding`) | Same |
| Cluster naming / tie-breaking on close calls | On-device Foundation Models | Real API model (Claude/GPT) |
| Periodic re-clustering pass | On-device, local scope | API-driven, reasons over a larger slice of history |
| What premium actually buys | — | Better splitting of messy, multi-topic notes; catching non-obvious connections across more history than the on-device context window allows |

**Does iOS 27 change this layer?** Not much. Multimodal input improves the *enrichment* layer (richer captions feeding into step 1 above), which indirectly improves clustering quality — but the graph layer's mechanism itself (embed → compare → threshold → escalate → periodically re-cluster) is version-agnostic and just inherits quality improvements automatically as enrichment gets better.

### 5. Surface layer
**What it does:** everything the user actually sees — timeline scrubbing, the current-state knowledge graph, quick-capture search, and LLM-written summaries (e.g. "this week you added 6 items to Math"). Reads from the ledger and graph; never writes back except through explicit user corrections.

**Why:** keeping this a pure read layer keeps the underlying data model simple and testable, and it's where most future UI experimentation happens without risking the integrity of the layers beneath it.

**View options:**

- **Timeline + filter chips** and **knowledge graph** are peer "home" views — the user picks which one they want as their default (or toggles between them), similar to a table/board view switcher. Both answer "what do I have right now," just with a different browsing feel: timeline is a familiar reverse-chronological feed with topic chips; the graph shows clusters as bubbles sized by item count, connected where related.
- **River view is not a third home option** — it's a per-cluster drill-down, not a standalone mode. Tap a topic chip in the timeline, or a bubble in the graph, and it opens the river scoped to *that one cluster*: a vertical, time-flowing view of tributary streams merging into it (e.g. "Math 1" and "Math 2" converging into "Math"), with dots along the streams representing individual commits. This is the view that makes the git "merge" and "blame" concepts tangible.
- Scoping the river to one cluster at a time (rather than all clusters simultaneously) is also what keeps it feasible to build — a global river with a dozen-plus parallel streams would be unreadable, but a single cluster's stream tree stays clean regardless of how large the graph overall gets.

**Why layer at all:** each layer depends only on the one below it, never sideways or upward. That's what makes the git properties real rather than cosmetic — history persists because the ledger never mutates, trust is preserved because graph and enrichment decisions are traceable back through the stack, and any single layer (a better on-device model, smarter clustering, iOS 27's multimodal input) can be upgraded without touching the others.

---

## Git-concept mapping

| Git concept | In this app | User-facing behavior |
|---|---|---|
| Commit | Every captured item | Immutable record: what, when, source |
| Commit log | Ledger layer | Full audit trail per item and per cluster |
| Tags / refs | Auto-extracted tags | Attached automatically at commit time, no manual typing |
| Blame | Cluster provenance | "This 'Math' cluster is built from these 14 notes and 2 whiteboard photos" |
| Diff | Timeline scrubbing | See how a topic looked last week vs. today |
| Branch | Parallel context | Work, a specific class, a side project develop independently |
| Merge | Auto-detected overlap | Two branches recognized as the same thread, merged visibly |
| Revert | Non-destructive correction | Wrong clustering is corrected via a new event, not a silent edit — and the correction feeds back into future tagging |

---

## User-facing outcomes

- **Trust** — the user can always trace back to why something ended up where it did; nothing is a black box.
- **Retrospective value** — "what did I add to this project in August" becomes a real review tool, not just search.
- **Forgiveness** — mistakes in auto-organizing are visible and correctable, not something the user has to just accept.
- **Narrative generation** — the LLM can summarize a cluster's history in plain language on a cadence (e.g. weekly recap), something current auto-organizing tools don't do.
- **Differentiation** — mymind and similar tools show the *current* organized state; this shows *how it got there*, which is the harder and more defensible thing to copy.

---

## Open considerations

- **Enrichment cost/latency**: on-device models (Apple Foundation Models, Vision) are fine for narrow tagging tasks but limited by context window (~4K tokens on-device) — large inputs need chunking before enrichment.
- **Merge false positives**: auto-merging branches needs a confidence threshold and an easy undo, since a wrong merge is more disruptive to trust than a wrong initial tag.
- **Cold start is a feature, not a gap to work around.** The feature should be visible from the very first commit, not held back until "enough" data exists:
  - A single commit with no existing clusters to compare against simply becomes its own singleton cluster/branch immediately (e.g. "Math 1"), visible in the timeline and graph right away.
  - A second, related-but-not-similar-enough commit can start its own singleton too (e.g. "Math 2") rather than being forced into an existing one.
  - As more commits arrive, the periodic re-clustering pass notices when singletons actually belong together and triggers a visible **merge event** ("Math 1 and Math 2 merged into Math") — turning the sparse early period into a visible growth story instead of a hidden ramp-up.
  - Bias early clustering toward creating new clusters over forcing weak matches — over-fragmenting is a cheap, recoverable mistake (fixed by a later merge); wrongly lumping unrelated items together is more disruptive to trust.
  - Run the re-clustering pass more frequently early in a user's lifecycle (e.g. every few commits in the first week) rather than only nightly, so a new user reaches their first "it just merged those" moment quickly.
