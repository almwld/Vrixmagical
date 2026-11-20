#!/usr/bin/env python3
"""Validate the repository-wide AI delegation and durable-memory contract."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / ".ai" / "registry.json"
REQUIRED_STATE = (
    "AI_TEAM.md",
    ".ai/README.md",
    ".ai/PROJECT_STATE.md",
    ".ai/decisions.md",
    ".ai/handoffs/current.md",
)


def fail(message: str) -> None:
    raise SystemExit(f"AI handoff validation failed: {message}")


def main() -> None:
    for relative in REQUIRED_STATE:
        if not (ROOT / relative).is_file():
            fail(f"missing required state file: {relative}")
    try:
        registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"registry is not valid JSON: {error}")

    if registry.get("version") != 1:
        fail("unsupported registry version")
    if registry.get("delegation_model") != "single-orchestrator":
        fail("delegation model must be single-orchestrator")

    skills = registry.get("skills")
    playbooks = registry.get("playbooks")
    if not isinstance(skills, list) or not skills:
        fail("registry must contain skills")
    if not isinstance(playbooks, list) or not playbooks:
        fail("registry must contain playbooks")

    skill_ids: set[str] = set()
    for skill in skills:
        required = ("id", "file", "description", "triggers", "inputs", "outputs", "validation")
        if any(key not in skill for key in required):
            fail(f"skill entry is missing required fields: {skill}")
        if skill["id"] in skill_ids:
            fail(f"duplicate skill id: {skill['id']}")
        skill_ids.add(skill["id"])
        path = ROOT / skill["file"]
        if not path.is_file():
            fail(f"skill file missing: {skill['file']}")
        content = path.read_text(encoding="utf-8")
        for heading in ("## Trigger", "## Inputs", "## Outputs", "## Validation"):
            if heading not in content:
                fail(f"{skill['file']} is missing section {heading}")

    playbook_ids: set[str] = set()
    for playbook in playbooks:
        required = ("id", "file", "purpose", "skills", "steps", "acceptance", "rollback")
        if any(key not in playbook for key in required):
            fail(f"playbook entry is missing required fields: {playbook}")
        if playbook["id"] in playbook_ids:
            fail(f"duplicate playbook id: {playbook['id']}")
        playbook_ids.add(playbook["id"])
        unknown = set(playbook["skills"]) - skill_ids
        if unknown:
            fail(f"{playbook['id']} references unknown skills: {sorted(unknown)}")
        path = ROOT / playbook["file"]
        if not path.is_file():
            fail(f"playbook file missing: {playbook['file']}")
        content = path.read_text(encoding="utf-8")
        for heading in ("## Goal", "## Steps", "## Acceptance"):
            if heading not in content:
                fail(f"{playbook['file']} is missing section {heading}")

    secret_patterns = (
        re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}"),
        re.compile(r"sk-[A-Za-z0-9]{24,}"),
        re.compile(r"AKIA[0-9A-Z]{16}"),
    )
    memory_files = [ROOT / "AI_TEAM.md", *sorted((ROOT / ".ai").rglob("*.md"))]
    for path in memory_files:
        content = path.read_text(encoding="utf-8")
        if any(pattern.search(content) for pattern in secret_patterns):
            fail(f"possible credential material found in {path.relative_to(ROOT)}")

    print(
        f"AI handoff contract valid: {len(skills)} skills, "
        f"{len(playbooks)} playbooks, {len(REQUIRED_STATE)} state files."
    )


if __name__ == "__main__":
    main()
