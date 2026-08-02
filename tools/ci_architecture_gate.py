#!/usr/bin/env python3
"""Architecture invariants for the privileged editor mutation core.

The behavioral test suite and this static gate serve different purposes. Hard
failures protect privileged boundaries. Module-size findings are warnings unless
they concern production code above the absolute God-class ceiling; test
registries are intentionally allowed to aggregate many cases.
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
        "_node_path_error",
        "FORBIDDEN_PROJECT_SETTINGS",
    ),
}

MAX_HARD_LINES = 900
WARN_LINES = 500
WARN_METHODS = 45


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def gdscript_files() -> list[Path]:
    return sorted((ROOT / "addons" / "ai_assistant").rglob("*.gd"))


def is_production_module(path: Path) -> bool:
    relative_parts = path.relative_to(ROOT).parts
    name = path.name
    return (
        not name.startswith("_")
        and not name.endswith("_test.gd")
        and "tests" not in relative_parts
        and "test" not in relative_parts
    )


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
        method_count = len(re.findall(r"(?m)^(?:static\s+)?func\s+", text))
        production = is_production_module(path)

        if production and lines > MAX_HARD_LINES:
            failures.append(
                f"{relative}: {lines} lines exceeds production God-class limit "
                f"{MAX_HARD_LINES}"
            )
        elif lines > WARN_LINES:
            kind = "production module" if production else "test/registry module"
            warnings.append(f"{relative}: large {kind} ({lines} lines)")

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
        # Direct mutations are permitted only inside private do/undo callback
        # methods registered with EditorUndoRedoManager. They remain visible as
        # warnings so reviewers inspect any newly introduced occurrence.
        direct_mutations = (
            "node.set(prop,",
            "node.set_script(res)",
            "parent.add_child(node)\n",
            "node.queue_free()\n",
        )
        for snippet in direct_mutations:
            if snippet in text:
                warnings.append(
                    f"{applier.relative_to(ROOT)}: inspect direct mutation callback: "
                    f"{snippet.strip()}"
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
