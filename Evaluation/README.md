# Remember grounded-answer evaluation

This provider-independent harness measures retrieval, long-memory and long-document questions, literal citation support, hallucination rejection, prompt-injection resistance, and abstention. It does not cover the removed Project feature and never uses a hosted judge to grade its own output.

## Fixtures

`Fixtures/remember_eval.jsonl` combines cases derived from LongMemEval, QASPER, RAGTruth, and original Remember adversarial examples. `Fixtures/remember_custom.jsonl` keeps the app-specific cases separately for review. Provenance and licensing details are in `THIRD_PARTY_NOTICES.md`.

The fixtures are developer data. They are not included in the iOS target and are never mixed with a user's vault.

## Prepare the suite

```bash
python3 scripts/prepare_remember_eval.py --per-source 20
```

The script can download public source datasets. For an offline run, pass its documented local-input flags. Suite selection and shuffling are deterministic.

## Result format and scoring

Run cases through the production retrieval and grounded-answer boundary, then write one JSON object per line:

```json
{"id":"remember-exact-id-001","answer":"Build 203 fixed it. [M1]","source_ids":["m1"],"citations":[{"source_id":"m1","excerpt":"Build 203 fixed RMM-1847"}],"mode":"grounded","latency_ms":842}
```

`mode` must be `grounded`, `partial`, `sourcesOnly`, or `noEvidence`. Citation excerpts must be literal substrings of the identified source.

Score a result file without a hosted judge:

```bash
python3 scripts/score_remember_eval.py \
  --fixture Evaluation/Fixtures/remember_eval.jsonl \
  --results Evaluation/Results/device.jsonl
```

API-backed evaluation requires the user to configure the proxy and key. Do not add secrets or raw private memories to result files. Re-run the suite whenever the model, prompt, retrieval, verification, or source-extraction behavior changes.
