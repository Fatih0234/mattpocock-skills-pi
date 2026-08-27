## What it does

`code-review` reviews the diff between `HEAD` and a fixed point you name (a commit, a branch, a tag, `main`, `HEAD~5`) along two axes. **Standards** asks whether the code follows how this repo writes code. **Spec** asks whether the code does what the originating issue or [spec](https://www.aihero.dev/ai-coding-dictionary/spec) asked for. Pi runs `standards-reviewer` and `spec-reviewer` in separate fresh model contexts so neither sees the other's reasoning. During a ticket-worker run, each reviewer uses `worktree: false` and inherits the worker cwd, so both inspect the actual implementation rather than a clean checkout. Each writes a separate artifact under `.scratch/pi-agents/`, and the owning worker or parent aggregates them.

The two axes are never merged and never re-ranked. The report ends with a worst issue *per axis* and refuses to name a single winner across them, because a change can pass one axis and fail the other: code that follows every convention while implementing the wrong thing passes Standards and fails Spec; code that does exactly what the [ticket](https://www.aihero.dev/ai-coding-dictionary/ticket) asked while breaking the repo's conventions does the reverse. A blended verdict lets the passing axis hide the failing one.

## When to reach for it

Type `/skill:code-review`, or the agent reaches for it automatically when you ask to review a branch, a PR, work in progress, or anything "since X".

| Your situation | Reach for |
| --- | --- |
| A diff exists and you want to know if it is built right *and* is the right thing | `code-review` |
| You want only a general bug hunt, without Standards or Spec axes | Ask for a focused bug review; this skill has a different contract |
| Nothing is written yet and you want it written test-first | [tdd](https://aihero.dev/skills-tdd) |
| A whole spec needs building, review included | [implement](https://aihero.dev/skills-implement), which calls this skill itself |
| The whole codebase has drifted, not one diff | [improve-codebase-architecture](https://aihero.dev/skills-improve-codebase-architecture) |
| Something is broken and you do not know why | [diagnosing-bugs](https://aihero.dev/skills-diagnosing-bugs) |

You must supply the fixed point. If you do not, the skill asks for one rather than guessing. It checks that the ref resolves and the diff is non-empty before delegating, so a mistyped branch name fails in the parent session.

## Prerequisites

The Standards axis needs nothing. It reads whatever the repo documents (`CODING_STANDARDS.md`, `CONTRIBUTING.md`, and the like) and falls back on a built-in baseline when the repo documents nothing.

The Spec axis needs a spec to exist and be findable. It looks in this order:

1. Issue references in the commit messages (`#123`, `Closes #45`, a GitLab `!67`), fetched through `docs/agents/issue-tracker.md`.
2. A path you pass in as an argument.
3. A spec file under `docs/`, `specs/`, or `.scratch/` matching the branch or feature name.
4. Asking you.

Step 1 depends on `docs/agents/issue-tracker.md`, which [setup-matt-pocock-skills](https://aihero.dev/skills-setup-matt-pocock-skills) writes. Without it the axis still works if you hand it a path. With no spec at all, `spec-reviewer` is skipped and the report says "no spec available" rather than inventing requirements.

## The two axes

| | Standards | Spec |
| --- | --- | --- |
| Question | Is it built right? | Is it the right thing? |
| Reads | The repo's documented standards, plus the smell baseline | The originating issue or spec |
| Reports | Documented breaches (can be hard), and smells (always judgement calls) | Missing or partial requirements, scope creep, requirements implemented wrongly |
| Every finding cites | The standards file and the rule, or the named smell plus the hunk | The line of the spec |

A generic review skill that does not know your standards is the thing this design is trying to avoid: it flags what is deliberate in your codebase and misses the invariants your codebase actually depends on. So the repo's own documentation is the [primary source](https://www.aihero.dev/ai-coding-dictionary/primary-source) on the Standards axis, and **the repo always overrides**.

The **smell baseline** is the floor underneath it, twelve Fowler code smells from _Refactoring_ ch.3: Mysterious Name, Duplicated Code, Feature Envy, Data Clumps, Primitive Obsession, Repeated Switches, Shotgun Surgery, Divergent Change, Speculative Generality, Message Chains, Middle Man, Refused Bequest. Each is a labelled heuristic ("possible Feature Envy"), never a hard violation, and each is stated as *what it is* → *how to fix*, so a finding arrives with a move attached rather than a complaint. Anything your linter already enforces is skipped by both axes.

## Common questions

**Can a reviewer recursively start another review?**

No. The Pi reviewer roles use explicit tool allowlists that exclude the `subagent` tool. They perform their assigned axis directly and cannot fan out into more agents.

**Should I run it in the same [session](https://www.aihero.dev/ai-coding-dictionary/session) that wrote the code?**

The parent session may be the implementation session because both review axes run in separate headless Pi contexts. The reviewers receive explicit briefs and do not inherit the parent's reasoning. Starting a fresh parent session is still useful when you also want the aggregation step to begin without implementation assumptions.

**After every ticket, or once at the end?**

Both work, and the skill does not decide for you. Per-ticket keeps each diff small enough that the Spec axis has one clear spec to check against, which is the mode `implement` uses. Batching to the end of a branch catches interactions between tickets that the per-ticket passes each miss. If you are unsure, review per ticket and run one final pass against the branch point.

**Can I trust the findings?**

Not without checking. Reviewer output is a hypothesis, not evidence. The parent aggregates the two artifacts without merging their axes, so a finding can still cite the wrong location or overstate an impact. Read the citation on each finding before acting on it. Every finding must carry a standards rule, a smell plus its hunk, or a spec requirement so the claim is checkable.

**Why does it find new problems every single time I run it?**

Because fixes create new surface, and because the judgement-call half of the Standards axis is not deterministic between runs. One reader described the loop plainly: "/code-review and /improve-code-architecture always find new stuff every time. I implement fixes, rerun these skills, and again and again." There is no convergence guarantee. Treat a pass as a list of leads, act on the ones with a cited rule behind them, and stop: do not run it in a loop until it comes back clean, because it will not.

**Does it review my uncommitted work?**

No. It diffs `<fixed-point>...HEAD`, three-dot, which is measured from the merge-base and excludes staged and working-tree changes. If `implement` has not made an interim commit, the work about to be committed is invisible to the review. Commit first, then review, then amend or add a fixup.

## It's working if

- It refuses to start on a bad ref or an empty diff, before delegation.
- `standards-reviewer` and `spec-reviewer` run in parallel isolated contexts and write separate artifacts.
- No reviewer changes a path outside its assigned artifact.
- The report arrives as two separate blocks under `## Standards` and `## Spec`, not one merged list.
- Every Standards finding names either a rule in one of your repo's files or one of the twelve smells, with the hunk quoted; every Spec finding quotes a line of the spec.
- The closing summary gives a worst issue per axis and declines to pick an overall winner.
- With no spec available, the Spec block says so instead of listing requirements it inferred from the code.

## Where it fits

`code-review` is the review step at the tail of the build chain: `grill-with-docs → to-spec → to-tickets → implement → code-review`. It also stands alone on any branch or PR you point it at.

- [implement](https://aihero.dev/skills-implement) is the closest neighbour: it drives the build and calls this skill as its own closing review before committing.
- [to-spec](https://aihero.dev/skills-to-spec) and [to-tickets](https://aihero.dev/skills-to-tickets) produce the document the Spec axis checks against; a vague spec makes that axis vague.
- [improve-codebase-architecture](https://aihero.dev/skills-improve-codebase-architecture) is the whole-codebase counterpart: this skill only ever looks at one diff.

[ask-matt](https://aihero.dev/skills-ask-matt) routes across the whole set when you are unsure which skill the situation wants.
