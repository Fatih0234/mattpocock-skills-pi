## What it does

`research` answers a question from the sources that own the answer, then leaves a cited Markdown file in the repo. It works from **[primary sources](https://www.aihero.dev/ai-coding-dictionary/primary-source)**: official documentation, specifications, first-party APIs, and source code.

The reading runs in an isolated headless Pi through the `researcher` role. The parent Pi waits for that delegated run to finish, validates its artifact and citations, then promotes the report from `.scratch/pi-agents/` to the repository's chosen research location. The researcher cannot invoke another subagent because its explicit tool allowlist excludes the `subagent` tool.

Research is legwork you delegate, not judgment you outsource. The report supplies facts for a later decision; it does not make the decision.

## When to reach for it

Type `/skill:research`, or the agent reaches for it automatically when a task turns into substantial reading legwork.

| What you need | Reach for |
| --- | --- |
| An external fact a decision is waiting on | `research` |
| A small fact available through a quick local lookup | Let the parent Pi look it up directly |
| A decision made with you by interview | [grilling](https://aihero.dev/skills-grilling) |
| A durable architecture decision | [grill-with-docs](https://aihero.dev/skills-grill-with-docs) |
| Evidence that an approach works in your codebase | [prototype](https://aihero.dev/skills-prototype) |
| A plan too large for one session | [wayfinder](https://aihero.dev/skills-wayfinder) |

The line between research and grilling is whether the blocker is a fact or a decision. A narrow, answerable question produces better research than a broad topic.

The parent allocates a unique scratch artifact such as:

```text
.scratch/pi-agents/research-20260827-101500/research.md
```

The researcher writes only that file and returns a short conclusion plus the path. The parent compares `git status --short` before and after delegation, reads the complete report, samples its citations, and chooses the final destination.

`pi-subagents` supports isolated contexts, managed worktrees, and asynchronous jobs. Parallel research belongs in one bounded `subagent` dispatch, as wayfinder does for independent research tickets. Read-only research runs should keep `worktree: false`; managed worktrees are for one owning ticket-worker.

## Common questions

**Why does the researcher write to scratch first?**

Scratch space creates a validation gate. The parent can reject weak citations, correct the destination, or discard stale research before it becomes normal project documentation. Existing documentation is never replaced by an unreviewed child process.

**Can the researcher modify source code or Git state?**

No. Its role permits one assigned report artifact. Project files, Git state, and tracker state remain read-only. The parent verifies the working tree after every dispatch.

**What counts as a primary source?**

Use the source that owns the claim: official documentation for a public API, the specification for protocol behavior, first-party source for implementation behavior, and first-party release notes for version changes. A secondary article can point toward evidence, but it cannot be the final citation for a material claim.

**Does a later session automatically reuse the report?**

No. The report becomes context only when a human, ticket, spec, or skill points to it. Link useful reports from the decision or implementation artifact they inform. Remove research that has become stale and has no durable consumer.

**How does wayfinder use this?**

Wayfinder groups independent research tickets into one parallel Pi subagent dispatch. Each `researcher` gets a unique artifact. The parent then validates the reports, posts the resolutions, closes the tickets, and updates the map. Researchers do not mutate tracker or Git state.

**What happens if the subagent tool is unavailable?**

The parent performs the same primary-source research in the current session and writes the report directly. It states that the work was not context-isolated.

## It's working if

- Exactly one `researcher` runs for a single research question.
- The only child-authored filesystem change is the assigned scratch artifact.
- Every material factual claim has a primary-source citation.
- The report distinguishes sourced fact, inference, and uncertainty.
- The parent validates the report before promoting it.
- The report alone is enough to make or sharpen the decision that requested it.

## Where it fits

Research is a standalone input to the thinking flows. [grilling](https://aihero.dev/skills-grilling) and [grill-with-docs](https://aihero.dev/skills-grill-with-docs) ask sharper questions when the facts are already available, and [to-spec](https://aihero.dev/skills-to-spec) can synthesize against the report. [wayfinder](https://aihero.dev/skills-wayfinder) invokes the same `researcher` role for AFK research tickets. [ask-matt](https://aihero.dev/skills-ask-matt) routes over the full set.
