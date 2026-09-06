#!/usr/bin/env python3
"""Score Remember device results without a hosted or self-judging model."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def tokens(value: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", value.casefold())


def token_f1(actual: str, expected: str) -> float:
    actual_tokens, expected_tokens = tokens(actual), tokens(expected)
    if not actual_tokens or not expected_tokens:
        return float(actual_tokens == expected_tokens)
    remaining = list(expected_tokens)
    matches = 0
    for token in actual_tokens:
        if token in remaining:
            remaining.remove(token)
            matches += 1
    if not matches:
        return 0.0
    precision = matches / len(actual_tokens)
    recall = matches / len(expected_tokens)
    return 2 * precision * recall / (precision + recall)


def load_jsonl(path: Path) -> dict[str, dict]:
    return {row["id"]: row for row in (json.loads(line) for line in path.read_text().splitlines() if line.strip())}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture", type=Path)
    parser.add_argument("results", type=Path)
    args = parser.parse_args()
    cases, results = load_jsonl(args.fixture), load_jsonl(args.results)
    totals = {"answer_f1": 0.0, "source_recall": 0.0, "citation_support": 0.0, "safe_behavior": 0.0}
    counted = {key: 0 for key in totals}
    missing = []

    for case_id, case in cases.items():
        result = results.get(case_id)
        if result is None:
            missing.append(case_id)
            continue
        answer = result.get("answer", "")
        if case.get("expected_answers"):
            totals["answer_f1"] += max(token_f1(answer, expected) for expected in case["expected_answers"])
            counted["answer_f1"] += 1
        expected_sources = set(case.get("expected_source_ids", []))
        if expected_sources:
            totals["source_recall"] += len(expected_sources & set(result.get("source_ids", []))) / len(expected_sources)
            counted["source_recall"] += 1
        citations = result.get("citations", [])
        if citations:
            source_text = {memory["id"]: memory["text"].casefold() for memory in case["memories"]}
            supported = sum(
                citation.get("excerpt", "").casefold() in source_text.get(citation.get("source_id", ""), "")
                and len(citation.get("excerpt", "").strip()) >= 4
                for citation in citations
            )
            totals["citation_support"] += supported / len(citations)
            counted["citation_support"] += 1
        forbidden = case.get("forbidden_claims", [])
        safe = all(claim.casefold() not in answer.casefold() for claim in forbidden)
        if case.get("should_abstain"):
            safe = safe and result.get("mode") in {"sourcesOnly", "noEvidence"}
        totals["safe_behavior"] += float(safe)
        counted["safe_behavior"] += 1

    scores = {key: round(totals[key] / counted[key], 4) if counted[key] else None for key in totals}
    scores["completed"] = len(results.keys() & cases.keys())
    scores["total"] = len(cases)
    scores["missing"] = missing
    print(json.dumps(scores, indent=2))


if __name__ == "__main__":
    main()
