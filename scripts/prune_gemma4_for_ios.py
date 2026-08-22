#!/usr/bin/env python3
"""Create a Gemma 4 text+vision checkpoint without unused audio tensors.

The transformation streams tensor byte ranges directly from the source
safetensors file. It does not deserialize model arrays or modify the source.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import struct
import sys
import tempfile
from pathlib import Path
from typing import Any, BinaryIO


EXCLUDED_PREFIXES = ("audio_tower.", "embed_audio.")
SAFETENSORS_FILENAME = "model.safetensors"
INDEX_FILENAME = "model.safetensors.index.json"
COPY_CHUNK_BYTES = 16 * 1024 * 1024


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Original Gemma 4 MLX model directory")
    parser.add_argument("destination", type=Path, help="New text+vision model directory")
    return parser.parse_args()


def read_header(source_file: BinaryIO) -> tuple[dict[str, Any], int]:
    encoded_length = source_file.read(8)
    if len(encoded_length) != 8:
        raise ValueError("The safetensors file is missing its header length.")
    header_length = struct.unpack("<Q", encoded_length)[0]
    encoded_header = source_file.read(header_length)
    if len(encoded_header) != header_length:
        raise ValueError("The safetensors header is truncated.")
    return json.loads(encoded_header), 8 + header_length


def padded_header(header: dict[str, Any]) -> bytes:
    encoded = json.dumps(header, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    padding = (-len(encoded)) % 8
    return encoded + (b" " * padding)


def copy_range(source: BinaryIO, destination: BinaryIO, offset: int, size: int) -> None:
    source.seek(offset)
    remaining = size
    while remaining:
        chunk = source.read(min(COPY_CHUNK_BYTES, remaining))
        if not chunk:
            raise ValueError("The safetensors data section is truncated.")
        destination.write(chunk)
        remaining -= len(chunk)


def make_pruned_safetensors(source_path: Path, destination_path: Path) -> tuple[int, int, int]:
    with source_path.open("rb") as source:
        header, source_data_offset = read_header(source)

        metadata = header.get("__metadata__")
        tensors: list[tuple[str, dict[str, Any]]] = []
        excluded_bytes = 0
        for name, specification in header.items():
            if name == "__metadata__":
                continue
            start, end = specification["data_offsets"]
            if any(name.startswith(prefix) for prefix in EXCLUDED_PREFIXES):
                excluded_bytes += end - start
                continue
            tensors.append((name, specification))

        tensors.sort(key=lambda item: item[1]["data_offsets"][0])
        new_header: dict[str, Any] = {}
        if metadata is not None:
            new_header["__metadata__"] = metadata

        next_offset = 0
        copy_plan: list[tuple[int, int]] = []
        for name, specification in tensors:
            old_start, old_end = specification["data_offsets"]
            size = old_end - old_start
            new_specification = dict(specification)
            new_specification["data_offsets"] = [next_offset, next_offset + size]
            new_header[name] = new_specification
            copy_plan.append((old_start, size))
            next_offset += size

        encoded_header = padded_header(new_header)
        destination_path.parent.mkdir(parents=True, exist_ok=True)
        with destination_path.open("wb") as destination:
            destination.write(struct.pack("<Q", len(encoded_header)))
            destination.write(encoded_header)
            for old_start, size in copy_plan:
                copy_range(source, destination, source_data_offset + old_start, size)
            destination.flush()
            os.fsync(destination.fileno())

    expected_size = 8 + len(encoded_header) + next_offset
    actual_size = destination_path.stat().st_size
    if actual_size != expected_size:
        raise ValueError(f"Generated file has {actual_size} bytes; expected {expected_size}.")
    return len(tensors), next_offset, excluded_bytes


def copy_sidecars(source: Path, destination: Path) -> None:
    for item in source.iterdir():
        if not item.is_file() or item.name in {SAFETENSORS_FILENAME, INDEX_FILENAME}:
            continue
        shutil.copy2(item, destination / item.name)


def write_index(source: Path, destination: Path, retained_names: set[str], total_size: int) -> None:
    source_index = source / INDEX_FILENAME
    if not source_index.exists():
        return
    index = json.loads(source_index.read_text(encoding="utf-8"))
    index["weight_map"] = {
        name: SAFETENSORS_FILENAME
        for name in index.get("weight_map", {})
        if name in retained_names
    }
    metadata = index.setdefault("metadata", {})
    if "total_size" in metadata:
        metadata["total_size"] = total_size
    (destination / INDEX_FILENAME).write_text(
        json.dumps(index, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def retained_tensor_names(model_file: Path) -> set[str]:
    with model_file.open("rb") as file:
        header, _ = read_header(file)
    return {name for name in header if name != "__metadata__"}


def main() -> int:
    arguments = parse_arguments()
    source = arguments.source.expanduser().resolve()
    destination = arguments.destination.expanduser().resolve()
    source_model = source / SAFETENSORS_FILENAME

    if not source_model.is_file():
        raise FileNotFoundError(f"Missing {source_model}")
    if destination.exists():
        raise FileExistsError(f"Destination already exists: {destination}")

    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=f".{destination.name}.", dir=destination.parent))
    try:
        tensor_count, retained_bytes, excluded_bytes = make_pruned_safetensors(
            source_model,
            staging / SAFETENSORS_FILENAME,
        )
        copy_sidecars(source, staging)
        names = retained_tensor_names(staging / SAFETENSORS_FILENAME)
        write_index(source, staging, names, retained_bytes)
        os.replace(staging, destination)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise

    print(f"Created {destination}")
    print(f"Retained {tensor_count} tensors ({retained_bytes / 1024 / 1024:.1f} MiB)")
    print(f"Removed unused audio tensors ({excluded_bytes / 1024 / 1024:.1f} MiB)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
