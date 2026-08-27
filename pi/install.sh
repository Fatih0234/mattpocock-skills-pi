#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_DIR="${PI_AGENT_DIR:-$HOME/.pi/agent}"
AGENTS_DEST="$AGENT_DIR/agents"
EXTENSIONS_DEST="$AGENT_DIR/extensions"
SETTINGS="$AGENT_DIR/settings.json"
NATIVE_SKILLS_ROOT="${PI_NATIVE_SKILLS_ROOT:-${PI_NATIVE_SKILLS_DIR:-$HOME/.agents/skills}}"
SUBAGENTS_PACKAGE="npm:pi-subagents@0.58.0"
SUBAGENTS_CONFIG_SOURCE="$ROOT/pi/subagents-config.json"
FAIL_AT="${PI_INSTALL_FAIL_AT:-}"
BACKUP=""
TRANSACTION_BACKUP=""
COMMITTED=false

declare -a TARGETS=()
declare -a TARGET_BACKUPS=()
declare -a TARGET_EXISTED=()

exists() { [ -e "$1" ] || [ -L "$1" ]; }

ensure_backup_dir() {
  if [ -z "$BACKUP" ]; then
    mkdir -p "$AGENT_DIR/backups"
    BACKUP="$(mktemp -d "$AGENT_DIR/backups/matt-skills-pi.XXXXXXXX")"
  fi
}

record_target() {
  local target="$1"
  ensure_backup_dir
  local index="${#TARGETS[@]}"
  local saved="$BACKUP/state/$index"
  mkdir -p "$(dirname "$saved")"
  TARGETS+=("$target")
  TARGET_BACKUPS+=("$saved")
  if exists "$target"; then
    cp -a "$target" "$saved"
    TARGET_EXISTED+=(1)
  else
    TARGET_EXISTED+=(0)
  fi
}

replace_target() {
  local target="$1"
  record_target "$target"
  rm -rf "$target"
}

link_managed() {
  local source="$1"
  local target="$2"
  if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$source")" ]; then
    printf 'already linked %s\n' "$target"
    return
  fi
  if [ ! -e "$source" ]; then
    echo "error: managed source does not exist: $source" >&2
    return 1
  fi
  replace_target "$target"
  mkdir -p "$(dirname "$target")"
  ln -s "$source" "$target"
  printf 'linked %s -> %s\n' "$target" "$source"
}

inject_failure() {
  local point="$1"
  if [ "$FAIL_AT" = "$point" ]; then
    echo "error: deterministic failure injected at $point" >&2
    return 1
  fi
}

restore_transaction() {
  if $COMMITTED; then return; fi
  set +e
  for ((index=${#TARGETS[@]}-1; index>=0; index--)); do
    rm -rf "${TARGETS[$index]}"
    if [ "${TARGET_EXISTED[$index]}" = 1 ]; then
      mkdir -p "$(dirname "${TARGETS[$index]}")"
      cp -a "${TARGET_BACKUPS[$index]}" "${TARGETS[$index]}"
    fi
  done
  if [ -n "$TRANSACTION_BACKUP" ]; then
    rm -rf "$AGENT_DIR/npm"
    if [ -e "$TRANSACTION_BACKUP/npm" ] || [ -L "$TRANSACTION_BACKUP/npm" ]; then
      cp -a "$TRANSACTION_BACKUP/npm" "$AGENT_DIR/npm"
    fi
  fi
  rm -rf "$TRANSACTION_BACKUP"
}
trap restore_transaction EXIT

mkdir -p "$AGENTS_DEST" "$EXTENSIONS_DEST" "$(dirname "$SETTINGS")" "$NATIVE_SKILLS_ROOT"
# Journal settings before creating a missing file. A failed first install must
# restore the absence, not leave behind a partial empty settings object.
record_target "$SETTINGS"
if [ ! -f "$SETTINGS" ]; then
  printf '{}\n' > "$SETTINGS"
fi
if [ ! -f "$SUBAGENTS_CONFIG_SOURCE" ]; then
  echo "error: missing pi-subagents configuration: $SUBAGENTS_CONFIG_SOURCE" >&2
  exit 1
fi

# Validate all immutable inputs before changing the live installation.
python3 - "$SUBAGENTS_CONFIG_SOURCE" "$SETTINGS" <<'PY'
import json
from pathlib import Path
import sys
source = json.loads(Path(sys.argv[1]).read_text())
if not isinstance(source, dict):
    raise SystemExit("error: pi-subagents config must be an object")
settings = json.loads(Path(sys.argv[2]).read_text())
if not isinstance(settings, dict):
    raise SystemExit("error: settings.json must be an object")
for key in ("packages", "skills"):
    value = settings.get(key, [])
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise SystemExit(f"error: settings.json {key!r} must be an array of strings")
PY

# An unrelated extension at the conventional path is never merged into or
# silently replaced. The old integration runtime is the only removable target.
legacy_runtime="$EXTENSIONS_DEST/subagent"
managed_legacy=false
if exists "$legacy_runtime"; then
  managed_legacy=false
  if [ -L "$legacy_runtime" ]; then
    legacy_source="$(readlink "$legacy_runtime")"
    case "$legacy_source" in
      "$ROOT/pi/extensions/subagent"|*/pi/extensions/subagent) managed_legacy=true ;;
    esac
  elif [ -d "$legacy_runtime" ] && [ -f "$legacy_runtime/index.ts" ] && [ -f "$legacy_runtime/UPSTREAM-SOURCE.txt" ]; then
    managed_legacy=true
  fi
  if ! $managed_legacy && [ ! -f "$legacy_runtime/config.json" ]; then
    echo "error: refusing to replace unrelated extension: $legacy_runtime" >&2
    exit 1
  fi
fi

# Keep a copy of the package-manager state until the handover commits. npm may
# contain unrelated Pi packages, so rollback restores the whole directory.
TRANSACTION_BACKUP="$(mktemp -d "$AGENT_DIR/.matt-skills-pi-transaction.XXXXXXXX")"
if [ -e "$AGENT_DIR/npm" ] || [ -L "$AGENT_DIR/npm" ]; then
  cp -a "$AGENT_DIR/npm" "$TRANSACTION_BACKUP/npm"
fi

# Install first while the previous runtime is still usable. pi install does not
# add package names to settings.json, so that manifest is staged explicitly below.
PI_CODING_AGENT_DIR="$AGENT_DIR" pi install "$SUBAGENTS_PACKAGE"
inject_failure after-package-install

# Archive sample roles installed by the initial experiment, then install the
# managed role links. All replacements are journaled for rollback.
for legacy in scout reviewer worker; do
  target="$AGENTS_DEST/$legacy.md"
  if [ -f "$target" ] && grep -q 'openai-codex/gpt-5.6-luna:high' "$target"; then
    replace_target "$target"
  fi
done
for source in "$ROOT"/pi/agents/*.md; do
  link_managed "$source" "$AGENTS_DEST/$(basename "$source")"
done

# Reconcile every promoted Matt skill into the native discovery root. This is
# deliberately an allowlist derived from the two promoted source buckets: stale
# native ask-matt/implement/code-review files cannot remain authoritative, while
# unrelated user-owned skills are untouched.
for source in "$ROOT"/skills/engineering/* "$ROOT"/skills/productivity/*; do
  [ -f "$source/SKILL.md" ] || continue
  link_managed "$source" "$NATIVE_SKILLS_ROOT/$(basename "$source")"
done

# Stage the new runtime config before retiring the old directory. Existing
# pi-subagents settings are merged so unrelated configuration survives.
config_stage="$(mktemp "$TRANSACTION_BACKUP/config.XXXXXX")"
python3 - "$SUBAGENTS_CONFIG_SOURCE" "$legacy_runtime/config.json" "$config_stage" <<'PY'
import json
from pathlib import Path
import sys
source = json.loads(Path(sys.argv[1]).read_text())
existing_path = Path(sys.argv[2])
existing = {}
if existing_path.is_file():
    existing = json.loads(existing_path.read_text())
if not isinstance(existing, dict):
    raise SystemExit("error: existing pi-subagents config must be an object")
merged = {**existing, **source}
if isinstance(existing.get("parallel"), dict) and isinstance(source.get("parallel"), dict):
    merged["parallel"] = {**existing["parallel"], **source["parallel"]}
Path(sys.argv[3]).write_text(json.dumps(merged, indent=2) + "\n")
PY

# Stage settings with exactly one pinned pi-subagents package and no old
# managed-skill roots. Preserve every unrelated skill/package entry.
settings_stage="$(mktemp "$TRANSACTION_BACKUP/settings.XXXXXX")"
python3 - "$SETTINGS" "$ROOT" "$NATIVE_SKILLS_ROOT" "$settings_stage" "$SUBAGENTS_PACKAGE" <<'PY'
import json
from pathlib import Path
import sys
settings_path, root, native_root, output = map(Path, sys.argv[1:5])
package = sys.argv[5]
settings = json.loads(settings_path.read_text())
if not isinstance(settings, dict):
    raise SystemExit("error: settings.json must be an object")
managed_roots = {
    str(Path(root) / "skills" / "engineering"),
    str(Path(root) / "skills" / "productivity"),
    str(Path(str(root).removesuffix("-pi")) / "skills" / "engineering"),
    str(Path(str(root).removesuffix("-pi")) / "skills" / "productivity"),
    str(Path(native_root)),
}
skills = settings.get("skills", [])
if not isinstance(skills, list) or not all(isinstance(item, str) for item in skills):
    raise SystemExit("error: settings.json 'skills' must be an array of strings")
settings["skills"] = [item for item in skills if item not in managed_roots]
if not settings["skills"]:
    settings.pop("skills", None)
packages = settings.get("packages", [])
if not isinstance(packages, list) or not all(isinstance(item, str) for item in packages):
    raise SystemExit("error: settings.json 'packages' must be an array of strings")
packages = [item for item in packages if "pi-subagents" not in item]
packages.append(package)
settings["packages"] = list(dict.fromkeys(packages))
settings["enableSkillCommands"] = True
output.write_text(json.dumps(settings, indent=2) + "\n")
PY

# Handover is the only destructive phase. Every operation remains covered by
# the transaction trap until both runtime config and settings are live.
if $managed_legacy; then
  replace_target "$legacy_runtime"
fi
mkdir -p "$legacy_runtime"
config_target="$legacy_runtime/config.json"
record_target "$config_target"
cp "$config_stage" "$config_target"
cp "$settings_stage" "$SETTINGS"
inject_failure after-runtime-handover
inject_failure after-settings

COMMITTED=true
rm -rf "$TRANSACTION_BACKUP"
TRANSACTION_BACKUP=""
printf '\nPi integration installed.\n'
printf 'Native skills: %s\n' "$NATIVE_SKILLS_ROOT"
printf 'Agents: %s\n' "$ROOT/pi/agents"
printf 'Runtime: %s\n' "$SUBAGENTS_PACKAGE"
printf 'Worktrees: ~/.cache/pi-subagents/worktrees\n'
printf 'Run /reload in an existing Pi session or start a new session.\n'
