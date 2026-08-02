#!/usr/bin/env python3
"""Architecture invariants for the privileged editor mutation core.

The test suite verifies behavior. This gate additionally prevents accidental
reintroduction of broad privileges and editor API anti-patterns before Godot is
started. It is intentionally narrow: hard failures protect security boundaries;
size/complexity findings are reported as warnings for planned refactoring.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "addons" / "ai_assistant" / "executor"

REQUIRED_FILES = {
    "editor_action_applier.gd",
    "executor_engine.gd",
    "scene_action_planner.gd",
    "_scene_action_planner_test.gd",
}

FORBIDDEN_GLOBAL_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "EditorInterface must not be resolved as an Engine extension singleton",
        re.compile(r'Engine\.(?:has_singleton|get_singleton)\(\s*["\']EditorInterface["\']'),
    ),
    (
        "generated code must not execute shell commands directly",
        re.compile(r"\bOS\.execute\s*\("),
    ),
)

REQUIRED_SNIPPETS: dict[str, tuple[str, ...]] = {
    "editor_action_applier.gd": (
        "EditorInterface.get_edited_scene_root()",
        "EditorInterface.get_editor_undo_redo()",
        "scene_file_path",
        "create_action(",
        "commit_action(",
    ),
    "executor_engine.gd": (
        "approve_destructive_action",
        "_consume_destructive_approval",
        "undo_token",
        "rollback",
    ),
    "scene_action_planner.gd": (
        "scene_path",
        "_validate_relative_node_path",
        "BLOCKED_PROJECT_SETTINGS",
    ),
}

MAX_HARD_LINES = 900
WARN_LINES = 500
WARN_METHODS = 45


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def gdscript_files() -> list[Path]:
    return sorted((ROOT / "addons" / "ai_assistant").rglob("*.gd"))


def main() -> int:
    failures: list[str] = []
    warnings: list[str] = []

    for filename in REQUIRED_FILES:
        path = CORE / filename
        if not path.is_file():
            failures.append(f"missing privileged-core file: {path.relative_to(ROOT)}")

    for path in gdscript_files():
        relative = path.relative_to(ROOT).as_posix()
        text = read(path)

        for reason, pattern in FORBIDDEN_GLOBAL_PATTERNS:
            if pattern.search(text):
                failures.append(f"{relative}: {reason}")

        lines = text.count("\n") + 1
        method_count = len(re.findall(r"(?m)^func\s+|^static func\s+", text))
        if lines > MAX_HARD_LINES:
            failures.append(
                f"{relative}: {lines} lines exceeds hard God-class limit {MAX_HARD_LINES}"
            )
        elif lines > WARN_LINES:
            warnings.append(f"{relative}: large module ({lines} lines)")

        if method_count > WARN_METHODS:
            warnings.append(f"{relative}: high method count ({method_count})")

    for filename, snippets in REQUIRED_SNIPPETS.items():
        path = CORE / filename
        if not path.is_file():
            continue
        text = read(path)
        for snippet in snippets:
            if snippet not in text:
                failures.append(
                    f"{path.relative_to(ROOT)}: required invariant missing: {snippet}"
                )

    applier = CORE / "editor_action_applier.gd"
    if applier.is_file():
        text = read(applier)
        direct_mutations = (
            "node.set(prop,",
            "node.set_script(res)",
            "parent.add_child(node)\n",
            "node.queue_free()\n",
        )
        for snippet in direct_mutations:
            if snippet in text:
                warnings.append(
                    f"{applier.relative_to(ROOT)}: inspect direct mutation occurrence: {snippet.strip()}"
                )

    if warnings:
        print("ARCHITECTURE_GATE_WARN")
        for warning in warnings:
            print(f"  - {warning}")

    if failures:
        print("ARCHITECTURE_GATE_FAIL")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("ARCHITECTURE_GATE_OK: privileged-core invariants preserved")
    return 0


if __name__ == "__main__":
    sys.exit(main())
