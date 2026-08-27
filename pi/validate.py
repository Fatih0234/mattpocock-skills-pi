#!/usr/bin/env python3
"""Validate the Pi adaptation without external dependencies."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
PROMOTED = (ROOT / "skills" / "engineering", ROOT / "skills" / "productivity")
ROLE_DIR = ROOT / "pi" / "agents"
MODEL = "openai-codex/gpt-5.6-luna:high"
SKILL_NAMES = {
    "ask-matt",
    "grill-with-docs",
    "grill-me",
    "grilling",
    "triage",
    "improve-codebase-architecture",
    "setup-matt-pocock-skills",
    "to-spec",
    "to-tickets",
    "implement",
    "wayfinder",
    "prototype",
    "diagnosing-bugs",
    "research",
    "tdd",
    "domain-modeling",
    "codebase-design",
    "code-review",
    "resolving-merge-conflicts",
    "wizard",
    "handoff",
    "teach",
    "to-questionnaire",
    "wait-what",
    "writing-for-agents",
}
EXPECTED_ROLES = {
    "repo-scout",
    "researcher",
    "standards-reviewer",
    "spec-reviewer",
    "interface-designer",
    "planner",
    "ticket-worker",
}
SUBAGENTS_PACKAGE = "npm:pi-subagents@0.58.0"
SUBAGENTS_CONFIG = ROOT / "pi" / "subagents-config.json"
errors: list[str] = []


def fail(path: Path | str, message: str) -> None:
    errors.append(f"{path}: {message}")


def frontmatter(path: Path) -> dict[str, str]:
    text = path.read_text()
    if not text.startswith("---\n"):
        fail(path, "missing YAML frontmatter")
        return {}
    parts = text.split("---\n", 2)
    if len(parts) < 3:
        fail(path, "unterminated YAML frontmatter")
        return {}
    raw = parts[1]
    result: dict[str, str] = {}
    for line in raw.splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            result[key.strip()] = value.strip().strip('"')
    return result


skill_files = sorted(path for root in PROMOTED for path in root.glob("*/SKILL.md"))
skill_names: list[str] = []
for path in skill_files:
    metadata = frontmatter(path)
    name = metadata.get("name")
    description = metadata.get("description")
    if not name:
        fail(path, "missing name")
    else:
        skill_names.append(name)
        if name != path.parent.name:
            fail(path, f"name {name!r} does not match directory")
    if not description:
        fail(path, "missing description")

    sidecar = path.parent / "agents" / "openai.yaml"
    if not sidecar.is_file():
        fail(sidecar, "missing Codex metadata")
    else:
        sidecar_text = sidecar.read_text()
        is_user_invoked = metadata.get("disable-model-invocation") == "true"
        has_false_policy = bool(re.search(r"^\s*allow_implicit_invocation:\s*false\s*$", sidecar_text, re.MULTILINE))
        has_policy_key = "allow_implicit_invocation:" in sidecar_text
        if is_user_invoked and not has_false_policy:
            fail(sidecar, "user-invoked skill must disable implicit invocation")
        if not is_user_invoked and has_policy_key:
            fail(sidecar, "model-invoked skill must omit implicit-invocation policy")

if set(skill_names) != SKILL_NAMES:
    fail("promoted skills", f"expected {sorted(SKILL_NAMES)}, got {sorted(set(skill_names))}")
if len(skill_names) != len(set(skill_names)):
    fail("promoted skills", "duplicate skill names")

plugin_path = ROOT / ".claude-plugin" / "plugin.json"
plugin = json.loads(plugin_path.read_text())
expected_plugin_paths = {
    f"./skills/{bucket}/{path.parent.name}"
    for bucket in ("engineering", "productivity")
    for path in (ROOT / "skills" / bucket).glob("*/SKILL.md")
}
plugin_paths = set(plugin["skills"])
if plugin_paths != expected_plugin_paths:
    fail(plugin_path, "promoted skill paths do not match discovered promoted directories")
for item in plugin_paths:
    resolved = ROOT / item
    if not resolved.is_dir() or not (resolved / "SKILL.md").is_file():
        fail(plugin_path, f"manifest path does not contain SKILL.md: {item}")

if not SUBAGENTS_CONFIG.is_file():
    fail(SUBAGENTS_CONFIG, "missing pi-subagents configuration")
else:
    try:
        config = json.loads(SUBAGENTS_CONFIG.read_text())
    except json.JSONDecodeError as error:
        fail(SUBAGENTS_CONFIG, f"invalid JSON: {error}")
        config = {}
    if not isinstance(config, dict):
        fail(SUBAGENTS_CONFIG, "configuration must be an object")
    else:
        if config.get("maxSubagentDepth") != 2:
            fail(SUBAGENTS_CONFIG, "maxSubagentDepth must enforce parent -> worker -> reviewer")
        if config.get("worktreeBaseDir") != "~/.cache/pi-subagents/worktrees":
            fail(SUBAGENTS_CONFIG, "worktreeBaseDir must use the Linux-side cache")
        if "/mnt/c" in str(config.get("worktreeBaseDir", "")):
            fail(SUBAGENTS_CONFIG, "worktreeBaseDir must not use /mnt/c")
        if config.get("maxActiveAsyncRunsPerSession") != 4:
            fail(SUBAGENTS_CONFIG, "implementation concurrency must be bounded at four")
        parallel = config.get("parallel")
        if not isinstance(parallel, dict):
            fail(SUBAGENTS_CONFIG, "parallel configuration must be an object")
        elif parallel.get("concurrency") != 4:
            fail(SUBAGENTS_CONFIG, "parallel concurrency must be four")
        install_script = ROOT / "pi" / "install.sh"
        if SUBAGENTS_PACKAGE not in install_script.read_text():
            fail(install_script, f"must install pinned {SUBAGENTS_PACKAGE}")
        legacy_runtime = ROOT / "pi" / "extensions" / "subagent"
        if legacy_runtime.exists():
            fail(legacy_runtime, "obsolete custom runtime must not be shipped")

role_files = sorted(ROLE_DIR.glob("*.md"))
role_names: set[str] = set()
for path in role_files:
    metadata = frontmatter(path)
    name = metadata.get("name", "")
    role_names.add(name)
    if metadata.get("model") != MODEL:
        fail(path, f"model must be {MODEL}")
    tools = {tool.strip() for tool in metadata.get("tools", "").split(",") if tool.strip()}
    if not tools:
        fail(path, "missing explicit tool allowlist")
    if name == "ticket-worker":
        if "subagent" not in tools:
            fail(path, "ticket-worker must invoke bounded nested reviews")
        if "edit" not in tools or "bash" not in tools:
            fail(path, "ticket-worker needs production editing and project commands")
        if "write" not in tools:
            fail(path, "ticket-worker must be able to write implementation files")
        if "worktree: false" not in path.read_text() or "fresh" not in path.read_text():
            fail(path, "ticket-worker must require fresh, shared-cwd nested reviews")
    else:
        forbidden = {"bash", "edit", "write", "subagent"}
        if tools & forbidden:
            fail(path, f"read-only role cannot expose mutation or delegation tools: {sorted(tools & forbidden)}")
        if tools != {"read", "grep", "find", "ls"}:
            fail(path, "read-only role must expose only inspection tools; runtime persists its report output")
    text = path.read_text()
    if name != "ticket-worker" and ("artifact path" not in text.lower() or "runtime persists" not in text.lower()):
        fail(path, "missing runtime-persisted assigned-artifact contract")

if role_names != EXPECTED_ROLES:
    fail(ROLE_DIR, f"expected roles {sorted(EXPECTED_ROLES)}, got {sorted(role_names)}")

markdown_files = [
    path
    for path in ROOT.rglob("*.md")
    if ".git" not in path.parts and ".pi" not in path.parts and "node_modules" not in path.parts
]

bare_skill = re.compile(r"`/(" + "|".join(sorted(map(re.escape, SKILL_NAMES), key=len, reverse=True)) + r")(?:\s|`)")
link_pattern = re.compile(r"\[[^]]*\]\(([^)]+)\)")
fenced_code = re.compile(r"```.*?```", re.DOTALL)

for path in sorted(set(markdown_files)):
    text = path.read_text()
    prose = fenced_code.sub("", text)
    # Upstream CHANGELOG history predates the repository's prose rule. Reject the
    # character everywhere maintained by this integration without rewriting history.
    if path != ROOT / "CHANGELOG.md" and "—" in text:
        fail(path, "contains an em dash")
    is_product_doc = path == ROOT / "README.md" or path.is_relative_to(ROOT / "docs")
    is_promoted = path.is_relative_to(PROMOTED[0]) or path.is_relative_to(PROMOTED[1])
    check_links = is_product_doc or is_promoted or path.is_relative_to(ROOT / "pi")
    if is_promoted:
        for phrase in ("Call the Skill tool", "call the Skill tool", "`/clear`"):
            if phrase in prose:
                fail(path, f"contains unsupported Pi mechanic {phrase!r}")
    match = bare_skill.search(prose) if is_product_doc or is_promoted else None
    if match:
        fail(path, f"uses bare skill command /{match.group(1)}")

    for target in link_pattern.findall(prose) if check_links else ():
        target = target.split()[0].strip("<>")
        if not target or target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        if path.is_relative_to(ROOT / "docs"):
            fail(path, f"docs page must use an absolute link: {target!r}")
            continue
        target = unquote(target.split("#", 1)[0])
        if not target:
            continue
        resolved = (path.parent / target).resolve()
        if not resolved.exists():
            fail(path, f"broken relative link {target!r}")

for bucket in ("engineering", "productivity"):
    for skill_dir in (ROOT / "skills" / bucket).iterdir():
        if not skill_dir.is_dir() or not (skill_dir / "SKILL.md").exists():
            continue
        doc = ROOT / "docs" / bucket / f"{skill_dir.name}.md"
        if not doc.exists():
            fail(doc, "missing promoted skill documentation")
            continue
        text = doc.read_text()
        for heading in ("## What it does", "## When to reach for it", "## Common questions", "## It's working if"):
            if heading not in text:
                fail(doc, f"missing section {heading!r}")

if errors:
    print("Pi integration validation failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    raise SystemExit(1)

print(f"Validated {len(skill_files)} promoted skills, {len(role_files)} Pi roles, and {len(set(markdown_files))} Markdown files.")
