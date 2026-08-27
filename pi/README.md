# Pi integration

This directory adapts Matt Pocock's promoted skills to the Pi coding agent while keeping the upstream `main` worktree clean.

## Operating model

`nicobailon/pi-subagents` is the only subagent runtime. The parent Pi owns the primary checkout, scheduling, supervision, user decisions, worker handoffs, sequential integration, conflict resolution, tracker state, and combined verification.

A `ticket-worker` owns exactly one managed Git worktree and is the normal production-writing role. Independent ready tickets may run concurrently within the configured bound. Worktree isolation is Git and filesystem isolation, not container or VM isolation: databases, ports, services, credentials, and other external resources remain shared.

Nested `standards-reviewer` and `spec-reviewer` children use fresh model contexts with `worktree: false`, inheriting the ticket-worker's cwd. They inspect the actual implementation and may write only their assigned review artifact. They cannot edit production files or delegate. The supported topology is parent -> ticket-worker -> reviewers, enforced with `maxSubagentDepth: 2`.

## Roles

- `repo-scout`: repository reconnaissance with evidence-linked findings
- `researcher`: primary-source research with citations
- `standards-reviewer`: independent review against repository standards and the smell baseline
- `spec-reviewer`: independent review against the originating specification
- `interface-designer`: one constrained deep-module design
- `planner`: dependency-aware implementation planning
- `ticket-worker`: one-ticket implementation, TDD, verification, nested review, commit, and handoff

Read-only roles use explicit allowlists and assigned-artifact contracts. `ticket-worker` alone has `edit` and `subagent` in its normal role allowlist.

## Runtime and configuration

The runtime is pinned to `npm:pi-subagents@0.58.0` and installed with Pi's package manager. Its configuration is copied to `~/.pi/agent/extensions/subagent/config.json` from `pi/subagents-config.json`:

- `defaultSubagentContext: fresh` gives each ticket a fresh implementation context.
- `maxSubagentDepth: 2` permits only parent -> worker -> reviewer delegation.
- `maxActiveAsyncRunsPerSession: 4` bounds active top-level runs. Because `runs.all` in pi-subagents 0.58.0 does not auto-throttle workflow children from `parallel.concurrency`, the parent must keep each writing wave at or below the configured `parallel.concurrency` value (4 by default). This is the scheduling policy, not an external-resource sandbox.
- `worktreeBaseDir: ~/.cache/pi-subagents/worktrees` keeps managed worktrees on the WSL Linux filesystem.

No worktree setup hook is configured because this repository has no required generated configuration or dependency bootstrap. Add one only if that changes, and keep secrets out of tracked paths.

## Installation and migration

```bash
./pi/install.sh
```

The installer links the role definitions into `~/.pi/agent/agents/`, installs the pinned npm package, merges the managed runtime configuration, and enables skill commands. It detects and archives only the previous managed custom extension at `~/.pi/agent/extensions/subagent/`; unrelated extensions are untouched. It reconciles the allowlisted adapted Matt skills into native `~/.agents/skills`, replacing stale managed copies while preserving unrelated user-owned skills. The in-progress `implement-spec` skill is not promoted. Running it repeatedly converges to the same settings, package, and native-skill state.

Run `/reload` in an existing Pi session after installation. Use `subagent({ action: "status" })`, FleetView, and `subagent_wait` to supervise asynchronous workers. Successful worktree runs expose pi-subagents' supported patch and handoff manifest; the parent verifies the base commit and applies completed handoffs sequentially to the primary checkout.

## Matt Pocock workflow

Matt skills remain the engineering workflow, not a competing runtime. Humans continue to use:

```text
/skill:grill-with-docs
/skill:to-spec
/skill:to-tickets
/skill:implement
```

`to-tickets` dependency edges determine the ready frontier. The parent chooses a conservative subset of independent ready tickets for dispatch, keeps each `runs.all` wave within the configured concurrency value, and does not treat readiness as automatic permission to parallelize. `ticket-worker` loads and follows the Matt implementation, TDD, code-review, and merge-conflict disciplines. Standards and Spec review stay separate and are evidence for the owning worker and parent to inspect.

## Reproducible source model

The clean `mattpocock-skills-upstream` worktree remains on upstream `main`. Pi-specific changes stay on the sibling `pi-integration` worktree. The dotfiles installer applies the versioned integration patches, checks the expected tree, and then runs this installer. Export changes only after validation and commit:

```bash
./pi/validate.py
./pi/smoke.sh              # deterministic installer/replacement checks
./pi/smoke.sh --runtime    # authenticated end-to-end worker/worktree canaries

# From the wsl-dotfiles checkout, after this worktree is committed:
MATPOCOCK_SKILLS_PI_WORKTREE="$PWD" \
  /path/to/wsl-dotfiles/scripts/export-mattpocock-pi.sh
```

The dotfiles snapshot exporter allowlists integration source and documentation paths and rejects credentials, sessions, model stores, and scratch artifacts.
