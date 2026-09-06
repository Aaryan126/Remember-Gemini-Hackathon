#!/usr/bin/env python3
"""Build a deterministic, source-attributed Remember evaluation JSONL file."""

from __future__ import annotations

import argparse
import json
import random
import urllib.parse
import urllib.request
from pathlib import Path


LONGMEM_URL = "https://huggingface.co/datasets/xiaowu0162/longmemeval-cleaned/resolve/main/longmemeval_oracle.json"
QASPER_ROWS_URL = "https://datasets-server.huggingface.co/rows"
RAGTRUTH_SOURCE_URL = "https://raw.githubusercontent.com/ParticleMedia/RAGTruth/main/dataset/source_info.jsonl"
RAGTRUTH_RESPONSE_URL = "https://raw.githubusercontent.com/ParticleMedia/RAGTruth/main/dataset/response.jsonl"


def download_json(url: str):
    with urllib.request.urlopen(url, timeout=120) as response:
        return json.load(response)


def download_jsonl(url: str):
    with urllib.request.urlopen(url, timeout=120) as response:
        return [json.loads(line) for line in response if line.strip()]


def read_json(path: Path | None, url: str):
    return json.loads(path.read_text()) if path else download_json(url)


def read_jsonl(path: Path | None, url: str):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()] if path else download_jsonl(url)


def longmem_cases(limit: int, path: Path | None = None) -> list[dict]:
    rows = read_json(path, LONGMEM_URL)
    selected = sorted(rows, key=lambda row: row["question_id"])[:limit]
    cases = []
    for row in selected:
        memories = []
        for session_id, date, turns in zip(
            row["haystack_session_ids"], row["haystack_dates"], row["haystack_sessions"]
        ):
            text = "\n".join(f'{turn["role"]}: {turn["content"]}' for turn in turns)
            memories.append({"id": session_id, "locator": date, "text": text})
        cases.append({
            "id": f'longmem-{row["question_id"]}',
            "dataset": "LongMemEval",
            "source_id": row["question_id"],
            "capability": "long_memory_qa",
            "query": row["question"],
            "memories": memories,
            "expected_answers": [row["answer"]],
            "expected_source_ids": row.get("answer_session_ids", []),
            "forbidden_claims": [],
            "should_abstain": False,
        })
    return cases


def qasper_cases(limit: int, path: Path | None = None) -> list[dict]:
    params = urllib.parse.urlencode({
        "dataset": "allenai/qasper", "config": "qasper", "split": "validation",
        "offset": 0, "length": min(100, max(limit, 10)),
    })
    rows = read_json(path, f"{QASPER_ROWS_URL}?{params}")["rows"]
    cases = []
    for wrapper in rows:
        paper = wrapper["row"]
        sections = paper["full_text"]
        memories = [
            {
                "id": f'{paper["id"]}-section-{index + 1}',
                "locator": name,
                "text": "\n".join(paragraphs),
            }
            for index, (name, paragraphs) in enumerate(zip(sections["section_name"], sections["paragraphs"]))
        ]
        qas = paper["qas"]
        for index, question in enumerate(qas["question"]):
            answers = qas["answers"][index]["answer"]
            expected = []
            evidence = []
            unanswerable = True
            for answer in answers:
                unanswerable = unanswerable and bool(answer.get("unanswerable"))
                if answer.get("yes_no") is not None:
                    expected.append("yes" if answer["yes_no"] else "no")
                expected.extend(answer.get("extractive_spans") or [])
                if answer.get("free_form_answer"):
                    expected.append(answer["free_form_answer"])
                evidence.extend(answer.get("evidence") or [])
            cases.append({
                "id": f'qasper-{qas["question_id"][index]}',
                "dataset": "QASPER",
                "source_id": qas["question_id"][index],
                "capability": "long_document_qa",
                "query": question,
                "memories": memories,
                "expected_answers": list(dict.fromkeys(expected)),
                "expected_source_ids": [],
                "expected_evidence": list(dict.fromkeys(evidence)),
                "forbidden_claims": [],
                "should_abstain": unanswerable,
            })
            if len(cases) >= limit:
                return cases
    return cases


def ragtruth_cases(limit: int, source_path: Path | None = None, response_path: Path | None = None) -> list[dict]:
    sources = {row["source_id"]: row for row in read_jsonl(source_path, RAGTRUTH_SOURCE_URL)}
    responses = [row for row in read_jsonl(response_path, RAGTRUTH_RESPONSE_URL) if row.get("labels")]
    selected = sorted(responses, key=lambda row: int(row["id"]))[:limit]
    cases = []
    for row in selected:
        source = sources[row["source_id"]]
        cases.append({
            "id": f'ragtruth-{row["id"]}',
            "dataset": "RAGTruth",
            "source_id": row["id"],
            "capability": "hallucination_rejection",
            "query": source["prompt"],
            "memories": [{"id": row["source_id"], "locator": source["source"], "text": source["source_info"]}],
            "candidate_answer": row["response"],
            "expected_answers": [],
            "expected_source_ids": [row["source_id"]],
            "forbidden_claims": [label["text"] for label in row["labels"]],
            "should_abstain": False,
        })
    return cases


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--per-source", type=int, default=20)
    parser.add_argument("--output", type=Path, default=Path("Evaluation/Fixtures/remember_eval.jsonl"))
    parser.add_argument("--custom", type=Path, default=Path("Evaluation/Fixtures/remember_custom.jsonl"))
    parser.add_argument("--longmem-input", type=Path)
    parser.add_argument("--qasper-input", type=Path)
    parser.add_argument("--ragtruth-source-input", type=Path)
    parser.add_argument("--ragtruth-response-input", type=Path)
    args = parser.parse_args()
    if not 1 <= args.per_source <= 100:
        parser.error("--per-source must be between 1 and 100")

    cases = (
        longmem_cases(args.per_source, args.longmem_input)
        + qasper_cases(args.per_source, args.qasper_input)
        + ragtruth_cases(args.per_source, args.ragtruth_source_input, args.ragtruth_response_input)
    )
    if args.custom.exists():
        cases.extend(json.loads(line) for line in args.custom.read_text().splitlines() if line.strip())
    random.Random(20260903).shuffle(cases)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("".join(json.dumps(case, ensure_ascii=False) + "\n" for case in cases))
    print(f"Wrote {len(cases)} cases to {args.output}")


if __name__ == "__main__":
    main()
