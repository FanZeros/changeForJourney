#!/usr/bin/env python3
"""Proof of concept: obfuscate one allowlisted Lua module in a separate build copy."""

import argparse
import hashlib
import re
from pathlib import Path

RELATIVE_MODULE = Path("scripts/shared/StageProvider.lua")
EXPECTED_LINES = [
    'local BaseStageConfig = require("config.StageConfig")',
    "local M = {}",
    "function M.Get()",
    "return BaseStageConfig",
    "end",
    "function M.GetForServer(_serverId)",
    "return BaseStageConfig",
    "end",
    "function M.IsAvailableForServer(_serverId)",
    "return true",
    "end",
    "function M.GetLoadError(_serverId)",
    "return nil",
    "end",
    "return M",
]


def obfuscate(source: str) -> str:
    lines = []
    for line in source.splitlines():
        line = line.strip()
        if not line or line.startswith("--"):
            continue
        if "--" in line:
            raise ValueError("unexpected inline comment: manual review required")
        lines.append(line)
    if lines != EXPECTED_LINES:
        raise ValueError("StageProvider has changed: manual review required")
    private_names = {"BaseStageConfig": "_a", "M": "_b"}
    tokens = re.compile(r"\b(?:BaseStageConfig|M)\b")
    result = ";".join(tokens.sub(lambda match: private_names[match.group()], line) for line in lines) + "\n"
    if result == source:
        raise ValueError("no obfuscation was performed")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description="StageProvider isolated obfuscation experiment")
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    source_root = args.source_root.resolve()
    output_root = args.output_root.resolve()
    if output_root == source_root or source_root in output_root.parents or output_root in source_root.parents:
        parser.error("output must be a separate directory outside the original source tree")
    src = source_root / RELATIVE_MODULE
    dst = output_root / RELATIVE_MODULE
    if not src.is_file():
        parser.error(f"missing module: {src}")
    original = src.read_text(encoding="utf-8")
    transformed = obfuscate(original)
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(transformed, encoding="utf-8")
    print(f"original_sha256={hashlib.sha256(original.encode()).hexdigest()}")
    print(f"obfuscated_sha256={hashlib.sha256(transformed.encode()).hexdigest()}")
    print(f"trial_file={dst}")


if __name__ == "__main__":
    main()
