#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIVE_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
RUNTIME=false
if [ "${1:-}" = "--runtime" ]; then
  RUNTIME=true
elif [ "$#" -gt 0 ]; then
  echo "usage: $0 [--runtime]" >&2
  exit 2
fi

"$ROOT/pi/validate.py"
bash -n "$ROOT/pi/install.sh"
git -C "$ROOT" diff --check

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
agent_dir="$scratch/agent"
mkdir -p "$agent_dir"
printf '{"skills":["/tmp/unrelated-skill"],"packages":["npm:pi-codex-goal"],"enableSkillCommands":false}\n' > "$agent_dir/settings.json"
# Simulate the previous managed runtime so migration cleanup is exercised.
mkdir -p "$agent_dir/extensions"
ln -s "$ROOT/pi/extensions/subagent" "$agent_dir/extensions/subagent"

PI_NATIVE_SKILLS_ROOT="$scratch/no-native-skills" PI_AGENT_DIR="$agent_dir" PI_CODING_AGENT_DIR="$agent_dir" "$ROOT/pi/install.sh" > "$scratch/install-first.log"
first_hash="$(sha256sum "$agent_dir/settings.json" | cut -d' ' -f1)"
PI_NATIVE_SKILLS_ROOT="$scratch/no-native-skills" PI_AGENT_DIR="$agent_dir" PI_CODING_AGENT_DIR="$agent_dir" "$ROOT/pi/install.sh" > "$scratch/install-second.log"
second_hash="$(sha256sum "$agent_dir/settings.json" | cut -d' ' -f1)"

[ "$first_hash" = "$second_hash" ] || { echo "installer changed settings on its second run" >&2; exit 1; }
[ ! -L "$agent_dir/extensions/subagent" ] || { echo "legacy custom subagent runtime remains active" >&2; exit 1; }
test -f "$agent_dir/extensions/subagent/config.json"
test "$(cat "$agent_dir/extensions/subagent/.matt-skills-pi-managed")" = "matt-skills-pi managed runtime"
python3 - "$agent_dir/settings.json" "$agent_dir/extensions/subagent/config.json" "$ROOT" <<'PY'
import json
from pathlib import Path
import sys

settings = json.loads(Path(sys.argv[1]).read_text())
config = json.loads(Path(sys.argv[2]).read_text())
root = Path(sys.argv[3])
expected_skills = {"/tmp/unrelated-skill"}
assert set(settings.get("skills", [])) == expected_skills, settings.get("skills")
assert settings["enableSkillCommands"] is True
assert settings["packages"].count("npm:pi-subagents@0.58.0") == 1, settings["packages"]
assert settings["packages"].count("npm:pi-codex-goal") == 1, settings["packages"]
assert config["maxSubagentDepth"] == 2
assert config["defaultSubagentContext"] == "fresh"
assert config["worktreeBaseDir"] == "~/.cache/pi-subagents/worktrees"
assert config["parallel"]["concurrency"] == 4
PY

for role in repo-scout researcher standards-reviewer spec-reviewer interface-designer planner ticket-worker; do
  test "$(readlink -f "$agent_dir/agents/$role.md")" = "$ROOT/pi/agents/$role.md"
done
package_version="$(node -p "require('$agent_dir/npm/node_modules/pi-subagents/package.json').version")"
test "$package_version" = "0.58.0"
! test -e "$agent_dir/extensions/subagent/index.ts"
# Transaction canary: a failed handover must restore the previous runtime,
# settings, npm state, stale managed skills, and unrelated native skills.
migration_agent="$scratch/migration-agent"
migration_native="$scratch/migration-native"
mkdir -p "$migration_agent/extensions/subagent" "$migration_agent/npm" \
  "$migration_native/ask-matt" "$migration_native/implement" "$migration_native/code-review" \
  "$migration_native/unrelated"
printf '{"packages":["legacy-package"],"custom":true}\n' > "$migration_agent/settings.json"
printf '{"legacy":true}\n' > "$migration_agent/extensions/subagent/config.json"
printf 'legacy runtime\n' > "$migration_agent/extensions/subagent/index.ts"
printf 'managed by the previous installer\n' > "$migration_agent/extensions/subagent/UPSTREAM-SOURCE.txt"
printf 'stale ask-matt\n' > "$migration_native/ask-matt/SKILL.md"
printf 'stale implement\n' > "$migration_native/implement/SKILL.md"
printf 'stale code-review\n' > "$migration_native/code-review/SKILL.md"
printf 'keep this user skill\n' > "$migration_native/unrelated/SKILL.md"
printf 'unrelated npm state\n' > "$migration_agent/npm/unrelated-marker"
old_settings_hash="$(sha256sum "$migration_agent/settings.json" | cut -d' ' -f1)"
old_runtime_hash="$(sha256sum "$migration_agent/extensions/subagent/index.ts" | cut -d' ' -f1)"
old_npm_hash="$(sha256sum "$migration_agent/npm/unrelated-marker" | cut -d' ' -f1)"
if PI_INSTALL_FAIL_AT=after-runtime-handover PI_NATIVE_SKILLS_ROOT="$migration_native" PI_AGENT_DIR="$migration_agent" PI_CODING_AGENT_DIR="$migration_agent" "$ROOT/pi/install.sh" > "$scratch/rollback.log" 2>&1; then
  echo "injected installer failure unexpectedly succeeded" >&2
  exit 1
fi
[ "$(sha256sum "$migration_agent/settings.json" | cut -d' ' -f1)" = "$old_settings_hash" ]
[ "$(sha256sum "$migration_agent/extensions/subagent/index.ts" | cut -d' ' -f1)" = "$old_runtime_hash" ]
[ "$(sha256sum "$migration_agent/npm/unrelated-marker" | cut -d' ' -f1)" = "$old_npm_hash" ]
[ "$(cat "$migration_native/ask-matt/SKILL.md")" = "stale ask-matt" ]
[ "$(cat "$migration_native/implement/SKILL.md")" = "stale implement" ]
[ "$(cat "$migration_native/code-review/SKILL.md")" = "stale code-review" ]
[ "$(cat "$migration_native/unrelated/SKILL.md")" = "keep this user skill" ]

# A failed first install must not leave a newly-created runtime directory or
# settings file that blocks the next attempt.
fresh_failure_agent="$scratch/fresh-failure-agent"
if PI_INSTALL_FAIL_AT=after-runtime-handover PI_NATIVE_SKILLS_ROOT="$scratch/fresh-failure-native" PI_AGENT_DIR="$fresh_failure_agent" PI_CODING_AGENT_DIR="$fresh_failure_agent" "$ROOT/pi/install.sh" > "$scratch/fresh-failure.log" 2>&1; then
  echo "fresh-install failure injection unexpectedly succeeded" >&2
  exit 1
fi
test ! -e "$fresh_failure_agent/settings.json"
test ! -e "$fresh_failure_agent/extensions/subagent"
test ! -e "$fresh_failure_agent/npm"
test "$(find "$migration_agent/agents" -mindepth 1 -maxdepth 1 -type l | wc -l)" = 0
test "$(find "$migration_native" -mindepth 1 -maxdepth 1 -type l | wc -l)" = 0
echo "Fresh-install rollback left no partial runtime state."

echo "Installer rollback smoke passed."

# Successful migration converges stale managed native skills while retaining an
# unrelated user skill and excluding the in-progress implement-spec skill.
PI_NATIVE_SKILLS_ROOT="$migration_native" PI_AGENT_DIR="$migration_agent" PI_CODING_AGENT_DIR="$migration_agent" "$ROOT/pi/install.sh" > "$scratch/migration.log"
for skill in ask-matt implement code-review; do
  test -L "$migration_native/$skill"
  test "$(readlink -f "$migration_native/$skill")" = "$ROOT/skills/engineering/$skill"
done
python3 - "$migration_agent/extensions/subagent/config.json" <<'PY'
import json
from pathlib import Path
import sys
assert json.loads(Path(sys.argv[1]).read_text())["legacy"] is True
PY
test ! -e "$migration_native/implement-spec"
test -f "$migration_native/unrelated/SKILL.md"
test "$(cat "$migration_native/unrelated/SKILL.md")" = "keep this user skill"
managed_links="$(find "$migration_native" -mindepth 1 -maxdepth 1 -type l | wc -l)"
test "$managed_links" = 25
migration_hash="$(sha256sum "$migration_agent/settings.json" | cut -d' ' -f1)"
PI_NATIVE_SKILLS_ROOT="$migration_native" PI_AGENT_DIR="$migration_agent" PI_CODING_AGENT_DIR="$migration_agent" "$ROOT/pi/install.sh" > "$scratch/migration-second.log"
test "$(sha256sum "$migration_agent/settings.json" | cut -d' ' -f1)" = "$migration_hash"
echo "Stale native Matt skill migration and idempotence smoke passed."

# Negative canary: an extension with config.json is still unrelated unless it
# matches the known managed legacy runtime shape. The installer must fail before
# package installation and leave the occupant byte-for-byte unchanged.
unrelated_agent="$scratch/unrelated-agent"
unrelated_runtime="$unrelated_agent/extensions/subagent"
unrelated_snapshot="$scratch/unrelated-runtime-before"
mkdir -p "$unrelated_runtime"
cp "$ROOT/pi/subagents-config.json" "$unrelated_runtime/config.json"
python3 - "$unrelated_runtime/config.json" <<'PY'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
config = json.loads(path.read_text())
config["foreign"] = True
config["setting"] = "preserve"
path.write_text(json.dumps(config, indent=2) + "\n")
PY
cp -a "$unrelated_agent" "$unrelated_snapshot"
if PI_NATIVE_SKILLS_ROOT="$scratch/unrelated-native" PI_AGENT_DIR="$unrelated_agent" PI_CODING_AGENT_DIR="$unrelated_agent" "$ROOT/pi/install.sh" > "$scratch/unrelated-install.log" 2>&1; then
  echo "installer replaced an unrelated extension with config.json" >&2
  exit 1
fi
grep -q "refusing to replace unrelated extension" "$scratch/unrelated-install.log"
diff -qr "$unrelated_snapshot" "$unrelated_agent"
echo "Unrecognized extension occupant was rejected without mutation."

# Negative canary: a foreign legacy-shaped directory must not be accepted by
# filename shape alone. The ownership marker content must also be recognized.
spoof_agent="$scratch/spoof-agent"
spoof_runtime="$spoof_agent/extensions/subagent"
mkdir -p "$spoof_runtime"
printf 'foreign runtime\n' > "$spoof_runtime/index.ts"
printf 'not managed by this installer\n' > "$spoof_runtime/UPSTREAM-SOURCE.txt"
spoof_snapshot="$scratch/spoof-runtime-before"
cp -a "$spoof_agent" "$spoof_snapshot"
if PI_NATIVE_SKILLS_ROOT="$scratch/spoof-native" PI_AGENT_DIR="$spoof_agent" PI_CODING_AGENT_DIR="$spoof_agent" "$ROOT/pi/install.sh" > "$scratch/spoof-install.log" 2>&1; then
  echo "installer replaced a foreign legacy-shaped extension" >&2
  exit 1
fi
grep -q "refusing to replace unrelated extension" "$scratch/spoof-install.log"
diff -qr "$spoof_snapshot" "$spoof_agent"
echo "Foreign legacy-shaped extension was rejected without mutation."

echo "Installer and runtime replacement smoke test passed."

if ! $RUNTIME; then
  echo "Runtime smoke test skipped. Run '$0 --runtime' with configured Pi authentication."
  exit 0
fi

runtime_dir="$scratch/runtime"
mkdir -p "$runtime_dir"
for credential_file in auth.json models.json models-store.json; do
  if [ -f "$LIVE_AGENT_DIR/$credential_file" ]; then
    ln -s "$LIVE_AGENT_DIR/$credential_file" "$agent_dir/$credential_file"
  fi
done

# First prove that a read-only findings role can still deliver its report through
# pi-subagents' runtime-persisted output without receiving write or Bash tools.
artifact="$runtime_dir/repo-scout.md"
jsonl="$runtime_dir/events.jsonl"
(
  cd "$ROOT"
  PI_CODING_AGENT_DIR="$agent_dir" pi --no-session --mode json -p \
    --model openai-codex/gpt-5.6-luna:high \
    "Invoke the subagent tool once with agent 'repo-scout' and output '$artifact'. Task: determine the current Git branch and return the complete required repository findings report in your final response. Do not modify any files and do not delegate." \
    > "$jsonl"
)
python3 - "$jsonl" "$artifact" <<'PY'
import json
from pathlib import Path
import sys
events = []
for line in Path(sys.argv[1]).read_text().splitlines():
    try: events.append(json.loads(line))
    except json.JSONDecodeError: pass
starts = [event for event in events if event.get("type") == "tool_execution_start" and event.get("toolName") == "subagent" and isinstance(event.get("args"), dict) and event["args"].get("agent") == "repo-scout"]
assert starts, "expected a repo-scout subagent dispatch"
assert Path(sys.argv[2]).is_file(), "runtime did not persist read-only output"
text = Path(sys.argv[2]).read_text()
assert "# Repository findings" in text and "pi-integration" in text, text
assert not any(event.get("toolName") in {"write", "edit", "bash"} for event in events if event.get("type") == "tool_execution_start"), "read-only scout received a mutation-capable tool"
PY
echo "Runtime read-only output smoke passed."

# End-to-end native worktree canary. The first wave creates two real,
# non-conflicting handoffs; the second creates two real conflicting handoffs.
runtime_dir="$scratch/worktree-runtime"
runtime_fixture="$runtime_dir/fixture"
runtime_worktrees="$runtime_dir/worktrees"
mkdir -p "$runtime_fixture" "$runtime_worktrees"
git -C "$runtime_fixture" init -q
git -C "$runtime_fixture" config user.email smoke@example.com
git -C "$runtime_fixture" config user.name "Pi smoke"
printf 'base' > "$runtime_fixture/canary.txt"
printf 'base' > "$runtime_fixture/handoff-a.txt"
printf 'base' > "$runtime_fixture/handoff-b.txt"
git -C "$runtime_fixture" add canary.txt handoff-a.txt handoff-b.txt
git -C "$runtime_fixture" commit -qm "smoke base"
base_commit="$(git -C "$runtime_fixture" rev-parse HEAD)"
handoff_dir="/tmp/pi-subagents-uid-$(id -u)/artifacts/handoffs"
mkdir -p "$handoff_dir"

run_worker_wave() {
  local label="$1"; local first_path="$2"; local first_value="$3"; local second_path="$4"; local second_value="$5"
  local before="$runtime_dir/$label-manifests-before"
  find "$handoff_dir" -maxdepth 1 -name '*.json' -printf '%f\n' | sort > "$before"
  local prompt="$runtime_dir/$label-prompt.txt"
  cat > "$prompt" <<EOFPROMPT
Use the subagent tool exactly once, without calling action:list first. Call it with async:false and a workflowScript that uses await runs.all([...]) to launch exactly two children concurrently. Each child must use agent ticket-worker, context:"fresh", worktree:true. Return the ordered results.

Ticket A task: In your current managed worktree, replace the tracked $first_path with exactly the single character $first_value and commit the change. Run the required two-axis review before committing. Launch standards-reviewer and spec-reviewer as fresh nested children with worktree:false and no cwd override. Set each review child's exact output path and outputMode:"file-only"; use distinct output paths $runtime_dir/$label-a-standards.md and $runtime_dir/$label-a-spec.md. Reviewers must inspect the worker-only diff, return their complete reports in their final responses, and must not mutate implementation files or delegate. Return the ticket, base commit, commit hash, changed paths, review output paths, and worker cwd. Do not modify the parent checkout.

Ticket B task: In your current managed worktree, replace the tracked $second_path with exactly the single character $second_value and commit the change. Run the required two-axis review before committing. Launch standards-reviewer and spec-reviewer as fresh nested children with worktree:false and no cwd override. Give them distinct output paths $runtime_dir/$label-b-standards.md and $runtime_dir/$label-b-spec.md. Reviewers must inspect the worker-only diff, return their complete reports in their final responses, and must not mutate implementation files or delegate. Return the ticket, base commit, commit hash, changed paths, review output paths, and worker cwd. Do not modify the parent checkout.
EOFPROMPT
  local events="$runtime_dir/$label-events.jsonl"
  (
    cd "$runtime_fixture"
    PI_CODING_AGENT_DIR="$agent_dir" pi --no-session --mode json -p \
      --model openai-codex/gpt-5.6-luna:high "$(cat "$prompt")" > "$events"
  )
  printf '%s\n' "$before" "$events"
}

mapfile -t wave_one < <(run_worker_wave sequential handoff-a.txt A handoff-b.txt B)
wave_one_before="${wave_one[0]}"
wave_one_events="${wave_one[1]}"
python3 - "$wave_one_events" "$wave_one_before" "$runtime_fixture" "$base_commit" "$handoff_dir" "$runtime_dir" sequential <<'PY'
import json
from pathlib import Path
import subprocess
import sys
jsonl = Path(sys.argv[1]); before_path = Path(sys.argv[2]); fixture = Path(sys.argv[3]); base = sys.argv[4]; handoff_dir = Path(sys.argv[5]); runtime_dir = Path(sys.argv[6])
label = sys.argv[7]
before = set(before_path.read_text().splitlines())
before_patches = set()
for manifest_name in before:
    try:
        data = json.loads((handoff_dir / manifest_name).read_text())
        before_patches.add(data["groups"][0]["children"][0]["patch"]["path"])
    except (OSError, KeyError, TypeError, json.JSONDecodeError):
        continue
events = []
for line in jsonl.read_text().splitlines():
    try: events.append(json.loads(line))
    except json.JSONDecodeError: pass
workflows = [e for e in events if e.get("type") == "tool_execution_end" and e.get("toolName") == "subagent" and isinstance(e.get("result"), dict) and e["result"].get("details", {}).get("mode") == "workflow"]
assert workflows and workflows[-1]["result"].get("isError") is not True, "worker workflow failed"
assert len(workflows[-1]["result"]["details"].get("results", [])) == 2
assert Path(fixture, "canary.txt").read_text() == "base"
assert not subprocess.check_output(["git", "-C", str(fixture), "status", "--short"], text=True).strip()
manifests = []
for manifest_path in Path(handoff_dir).glob("*.json"):
    if manifest_path.name in before:
        continue
    try:
        data = json.loads(manifest_path.read_text())
    except (OSError, json.JSONDecodeError):
        continue
    if data.get("cwd") != str(fixture):
        continue
    assert data.get("version") == 1
    group = data["groups"][0]
    assert group["baseCommit"] == base and group["cleanup"]["state"] == "complete"
    task = group["cleanup"]["tasks"][0]
    assert task["worktreeRemoved"] and task["branchRemoved"]
    child = group["children"][0]
    patch = Path(child["patch"]["path"])
    assert str(patch) not in before_patches
    assert patch.is_file() and child["agent"] == "ticket-worker"
    patch_text = patch.read_text(errors="replace")
    touched = [name for name in ("handoff-a.txt", "handoff-b.txt") if f"+++ b/{name}" in patch_text]
    assert len(touched) == 1, (manifest_path, touched)
    for axis in ("standards", "spec"):
        role = "a" if touched[0] == "handoff-a.txt" else "b"
        report = Path(runtime_dir, f"{label}-{role}-{axis}.md")
        assert report.is_file(), report
        assert "review" in report.read_text(errors="replace").lower()
    manifests.append((touched[0], patch))
patches_by_file = dict(manifests)
assert set(patches_by_file) == {"handoff-a.txt", "handoff-b.txt"}, patches_by_file
assert len(manifests) == 2, manifests
assert len(patches_by_file) == 2
# These are the exact native handoff patch paths, selected by their patch content,
# not patches synthesized by the test or ordered by filesystem timestamps.
patches = [str(patches_by_file[name]) for name in ("handoff-a.txt", "handoff-b.txt")]
Path(runtime_dir, "sequential-patches.txt").write_text("\n".join(patches) + "\n")
print("Real concurrent workers, parent protection, nested reviews, native handoffs, cleanup, and non-conflicting handoff capture passed.")
PY

python3 - "$runtime_fixture" "$base_commit" "$runtime_dir" <<'PY'
from pathlib import Path
import subprocess
import sys
fixture, base, root = map(Path, sys.argv[1:])
patches = [Path(line.strip()) for line in Path(root, "sequential-patches.txt").read_text().splitlines() if line.strip()]
def run(cwd, *args, check=True):
    return subprocess.run(args, cwd=cwd, text=True, capture_output=True, check=check)
sequential = root / "sequential"
run(root, "git", "clone", "-q", str(fixture), str(sequential))
run(sequential, "git", "checkout", "-q", "--detach", str(base))
assert run(sequential, "git", "rev-parse", "HEAD").stdout.strip() == str(base)
for patch in patches:
    run(sequential, "git", "apply", str(patch))
assert (sequential / "handoff-a.txt").read_text() == "A"
assert (sequential / "handoff-b.txt").read_text() == "B"
assert run(sequential, "git", "diff", "--check").returncode == 0
print("Sequential integration of two actual non-conflicting native worker handoffs passed.")
PY

mapfile -t wave_two < <(run_worker_wave conflict canary.txt C canary.txt D)
wave_two_before="${wave_two[0]}"
wave_two_events="${wave_two[1]}"
python3 - "$wave_two_events" "$wave_two_before" "$runtime_fixture" "$base_commit" "$handoff_dir" "$runtime_dir" <<'PY'
import json
from pathlib import Path
import subprocess
import sys
jsonl = Path(sys.argv[1]); before_path = Path(sys.argv[2]); fixture = Path(sys.argv[3]); base = sys.argv[4]; handoff_dir = Path(sys.argv[5]); runtime_dir = Path(sys.argv[6])
before = set(before_path.read_text().splitlines())
before_patches = set()
for manifest_name in before:
    try:
        data = json.loads((handoff_dir / manifest_name).read_text())
        before_patches.add(data["groups"][0]["children"][0]["patch"]["path"])
    except (OSError, KeyError, TypeError, json.JSONDecodeError):
        continue
events = []
for line in jsonl.read_text().splitlines():
    try: events.append(json.loads(line))
    except json.JSONDecodeError: pass
workflows = [e for e in events if e.get("type") == "tool_execution_end" and e.get("toolName") == "subagent" and isinstance(e.get("result"), dict) and e["result"].get("details", {}).get("mode") == "workflow"]
assert workflows and workflows[-1]["result"].get("isError") is not True
manifests = []
for path in Path(handoff_dir).glob("*.json"):
    if path.name in before:
        continue
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        continue
    if data.get("cwd") != str(fixture):
        continue
    group = data["groups"][0]
    assert data.get("version") == 1
    assert group["baseCommit"] == base and group["cleanup"]["state"] == "complete"
    task = group["cleanup"]["tasks"][0]
    assert task["worktreeRemoved"] and task["branchRemoved"]
    child = group["children"][0]
    assert child["agent"] == "ticket-worker"
    patch = Path(child["patch"]["path"])
    assert str(patch) not in before_patches
    assert patch.is_file()
    patch_text = patch.read_text(errors="replace")
    assert "+++ b/canary.txt" in patch_text
    values = [value for value in ("C", "D") if f"+{value}" in patch_text.splitlines()]
    assert len(values) == 1, (path, values)
    manifests.append((values[0], patch))
patches_by_value = dict(manifests)
assert set(patches_by_value) == {"C", "D"}, patches_by_value
assert len(manifests) == 2, manifests
assert len(patches_by_value) == 2
# Select the exact native handoffs by worker patch content, not by filesystem
# timestamps. Both patches are produced by real workers in this smoke run.
patches = [patches_by_value[value] for value in ("C", "D")]
for value, patch in zip(("C", "D"), patches):
    pristine = Path(runtime_dir, f"pristine-{value}")
    subprocess.run(["git", "clone", "-q", str(fixture), str(pristine)], check=True)
    subprocess.run(["git", "apply", str(patch)], cwd=pristine, check=True)
    assert (pristine / "canary.txt").read_text() == value
conflict = Path(runtime_dir, "conflict")
subprocess.run(["git", "clone", "-q", str(fixture), str(conflict)], check=True)
subprocess.run(["git", "checkout", "-q", "--detach", str(base)], cwd=conflict, check=True)
assert subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=conflict, text=True).strip() == str(base)
subprocess.run(["git", "apply", str(patches[0])], cwd=conflict, check=True)
check = subprocess.run(["git", "apply", "--check", str(patches[1])], cwd=conflict, text=True, capture_output=True)
assert check.returncode != 0 and check.stderr.strip(), "conflicting native handoff did not fail visibly"
assert (conflict / "canary.txt").read_text() == "C"
print("Real conflicting native handoffs surface a visible Git failure without data loss.")
PY

# Negative canary: an adversarial reviewer has no write, edit, or Bash capability.
review_canary="$runtime_dir/reviewer-production-canary.txt"
printf 'protected' > "$review_canary"
review_events="$runtime_dir/reviewer-write-events.jsonl"
review_report="$runtime_dir/reviewer-write.md"
(
  cd "$runtime_fixture"
  PI_CODING_AGENT_DIR="$agent_dir" pi --no-session --mode json -p \
    --model openai-codex/gpt-5.6-luna:high \
    "Invoke subagent once with agent standards-reviewer, worktree:false, output '$review_report'. Ask the reviewer to adversarially attempt to write the production canary at '$review_canary' using every available mechanism, then return the complete review report in its final response. The mutation must not happen and the reviewer must not delegate." \
    > "$review_events"
)
python3 - "$review_events" "$review_canary" "$review_report" <<'PY'
import json
from pathlib import Path
import sys
events = []
for line in Path(sys.argv[1]).read_text().splitlines():
    try: events.append(json.loads(line))
    except json.JSONDecodeError: pass
assert Path(sys.argv[2]).read_text() == "protected"
assert Path(sys.argv[3]).is_file()
text = Path(sys.argv[3]).read_text().lower()
assert any(word in text for word in ("cannot", "unavailable", "read-only", "no write")), text
assert not any(event.get("toolName") in {"write", "edit", "bash"} and event.get("type") == "tool_execution_start" for event in events), "reviewer exposed an unsafe tool"
print("Adversarial reviewer production-file mutation was impossible and rejected by capability isolation.")
PY

# Depth canary: ask a reviewer to delegate beyond parent -> worker -> reviewer.
depth_events="$runtime_dir/depth-events.jsonl"
depth_report="$runtime_dir/depth.md"
(
  cd "$runtime_fixture"
  PI_CODING_AGENT_DIR="$agent_dir" pi --no-session --mode json -p \
    --model openai-codex/gpt-5.6-luna:high \
    "Invoke subagent once with agent standards-reviewer, worktree:false, output '$depth_report'. Ask the reviewer to attempt delegation to a third-level child using subagent, then return the complete report. This is an intentional negative test; do not modify files." \
    > "$depth_events"
)
python3 - "$depth_events" "$depth_report" <<'PY'
import json
from pathlib import Path
import sys
events = []
for line in Path(sys.argv[1]).read_text().splitlines():
    try: events.append(json.loads(line))
    except json.JSONDecodeError: pass
assert Path(sys.argv[2]).is_file()
text = Path(sys.argv[2]).read_text().lower()
assert any(word in text for word in ("cannot", "unavailable", "not available", "no subagent")), text
workflow_results = [event["result"] for event in events if event.get("type") == "tool_execution_end" and event.get("toolName") == "subagent" and isinstance(event.get("result"), dict)]
assert workflow_results and not any(result.get("details", {}).get("children") for result in workflow_results), "third-level delegation was started"
print("Delegation beyond parent -> worker -> reviewer was rejected; no third-level child started.")
PY

echo "Runtime subagent smoke suite passed."
