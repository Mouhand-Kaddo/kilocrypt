#!/usr/bin/env python3
"""Emit a C header splitting a GLSL file into <= 12 KB string literals (MSVC C2026 safe)."""
import sys

src_path, out_path = sys.argv[1], sys.argv[2]
text = open(src_path, "r", encoding="utf-8").read().replace("\r\n", "\n")

chunks, buf, size = [], [], 0
for line in text.splitlines(keepends=True):
    enc = line.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    if size + len(enc) > 10000 and buf:
        chunks.append(buf)
        buf, size = [], 0
    buf.append(f'"{enc}"')
    size += len(enc)
if buf:
    chunks.append(buf)

with open(out_path, "w", encoding="utf-8") as f:
    f.write("/* Generated from " + src_path + " by tools/embed_shader.py */\n")
    f.write("#define SHADER_PARTS_LIST \\\n")
    for i, c in enumerate(chunks):
        sep = ", \\" if i + 1 < len(chunks) else ""
        f.write("    " + " \\\n    ".join(c) + sep + "\n")
