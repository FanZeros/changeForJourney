#!/usr/bin/env python3
"""Isolated Lua trial: one-module renaming or full-project comment stripping."""

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


def strip_comments(source: str) -> str:
    """Remove non-annotation Lua comments and indentation, retaining LSP types."""
    out = []
    i = 0
    line_start = True
    while i < len(source):
        ch = source[i]
        if line_start and ch in " \t":
            i += 1
            continue
        if ch in "\"'":
            start = i
            quote = ch
            i += 1
            while i < len(source):
                if source[i] == "\\":
                    i += 2
                elif source[i] == quote:
                    i += 1
                    break
                else:
                    i += 1
            else:
                raise ValueError("unterminated quoted string")
            out.append(source[start:i])
            line_start = False
            continue
        if ch == "[" or source.startswith("--[", i):
            bracket = i + 2 if source.startswith("--[", i) else i
            match = re.match(r"\[(=*)\[", source[bracket:])
            if match:
                close = "]" + match.group(1) + "]"
                end = source.find(close, bracket + len(match.group()))
                if end < 0:
                    raise ValueError("unterminated long bracket")
                chunk = source[i:end + len(close)]
                if bracket == i:
                    out.append(chunk)
                    line_start = chunk.endswith("\n")
                else:
                    if chunk.startswith("--[[@"):
                        out.append(chunk)
                        line_start = False
                        i = end + len(close)
                        continue
                    newlines = chunk.count("\n")
                    out.append("\n" * newlines if newlines else " ")
                    line_start = newlines > 0 and chunk.endswith("\n")
                i = end + len(close)
                continue
        if source.startswith("--", i):
            end = source.find("\n", i)
            if source.startswith("---", i):
                # Preserve EmmyLua annotations required by the official LSP check.
                stop = len(source) if end < 0 else end
                out.append(source[i:stop])
                i = stop
                continue
            i = len(source) if end < 0 else end
            continue
        if ch == "\n":
            while out and out[-1] in (" ", "\t"):
                out.pop()
        out.append(ch)
        line_start = ch == "\n"
        i += 1
    return "".join(out)


def obfuscate_all(source_root: Path, output_root: Path) -> None:
    files = sorted((source_root / "scripts").rglob("*.lua"))
    if not files:
        raise ValueError("no Lua scripts found")
    if output_root.exists():
        raise ValueError("output directory already exists; choose a fresh directory")
    transformed = []
    for src in files:
        original = src.read_text(encoding="utf-8")
        result = strip_comments(original)
        if strip_comments(result) != result:
            raise ValueError(f"not idempotent: {src}")
        transformed.append((src.relative_to(source_root), result, len(original.encode("utf-8"))))
    for relative, result, _ in transformed:
        dst = output_root / relative
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(result, encoding="utf-8")
    changed = sum(1 for relative, result, _ in transformed
                  if result != (source_root / relative).read_text(encoding="utf-8"))
    print(f"trial_files={len(files)} changed={changed} original_bytes={sum(size for _, _, size in transformed)} "
          f"output_bytes={sum(len(result.encode('utf-8')) for _, result, _ in transformed)}")
    print(f"trial_scripts={output_root / 'scripts'}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Isolated Lua obfuscation experiment")
    parser.add_argument("--all-scripts", action="store_true", help="strip comments and indentation from every Lua script in an isolated output")
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    source_root = args.source_root.resolve()
    output_root = args.output_root.resolve()
    if output_root == source_root or source_root in output_root.parents or output_root in source_root.parents:
        parser.error("output must be a separate directory outside the original source tree")
    if args.all_scripts:
        obfuscate_all(source_root, output_root)
        return
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
