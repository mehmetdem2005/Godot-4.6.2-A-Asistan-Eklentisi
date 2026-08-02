#!/usr/bin/env python3
"""Repository secret and credential leakage gate.

This scanner is intentionally dependency-free so it can run in GitHub Actions
and locally. It scans Git-tracked text files, rejects known credential formats,
private-key material, unsafe Authorization literals, and secret-bearing files.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAX_TEXT_BYTES = 2 * 1024 * 1024

BLOCKED_SUFFIXES = {
    ".jks",
    ".keystore",
    ".p12",
    ".pfx",
    ".pem",
}
BLOCKED_FILENAMES = {
    ".env",
    "credentials.json",
    "service-account.json",
    "ai_assistant_keys.dat",
}

PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("private key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
    ("GitHub classic token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b")),
    ("GitHub fine-grained token", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{40,}\b")),
    ("AWS access key", re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")),
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("Anthropic API key", re.compile(r"\bsk-ant-[A-Za-z0-9_-]{30,}\b")),
    ("OpenAI project key", re.compile(r"\bsk-(?:proj|svcacct)-[A-Za-z0-9_-]{30,}\b")),
    ("generic long sk token", re.compile(r"\bsk-[A-Za-z0-9]{48,}\b")),
    (
        "literal bearer credential",
        re.compile(r"Authorization\s*:\s*Bearer\s+[A-Za-z0-9._~+/=-]{24,}", re.IGNORECASE),
    ),
)

SAFE_TEXT_MARKERS = (
    "example",
    "placeholder",
    "redacted",
    "dummy",
    "fake",
    "test-key",
    "sk-test",
    "<token>",
    "${",
    "$GITHUB_",
)


def tracked_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    return [ROOT / item.decode("utf-8") for item in result.stdout.split(b"\0") if item]


def is_probably_text(data: bytes) -> bool:
    if b"\0" in data[:4096]:
        return False
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        return False
    return True


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def main() -> int:
    findings: list[str] = []

    for path in tracked_files():
        relative = path.relative_to(ROOT).as_posix()
        lower_name = path.name.lower()

        if lower_name in BLOCKED_FILENAMES or path.suffix.lower() in BLOCKED_SUFFIXES:
            findings.append(f"{relative}: secret-bearing file type is forbidden")
            continue

        try:
            data = path.read_bytes()
        except OSError as exc:
            findings.append(f"{relative}: cannot read tracked file: {exc}")
            continue

        if len(data) > MAX_TEXT_BYTES or not is_probably_text(data):
            continue

        text = data.decode("utf-8")
        text_lower = text.lower()

        for label, pattern in PATTERNS:
            for match in pattern.finditer(text):
                start = max(0, match.start() - 100)
                end = min(len(text), match.end() + 100)
                context = text_lower[start:end]
                if any(marker.lower() in context for marker in SAFE_TEXT_MARKERS):
                    continue
                findings.append(
                    f"{relative}:{line_number(text, match.start())}: possible {label}"
                )

    if findings:
        print("SECURITY_GATE_FAIL")
        for finding in findings:
            print(f"  - {finding}")
        return 1

    print("SECURITY_GATE_OK: no tracked credential material detected")
    return 0


if __name__ == "__main__":
    sys.exit(main())
