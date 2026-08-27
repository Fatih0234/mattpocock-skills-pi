# Phase boundaries

A **phase** is a chunk of work inside a session: the grilling, the implementation, the QA. The definition is fuzzy on purpose: a phase ends when you think *"ok, we're done with that"*.

The **phase boundary** is the gap between two phases, and it is the only place this decision belongs. Mid-phase there is no decision to make: continue, delegate a bounded AFK task, or use `/split-fork` for an interactive side task. Compacting mid-phase makes the agent lose the thread.

## The six options

| Option | What it does |
| --- | --- |
| **Continue** | Stay in the session. No context switch at all. |
| **`/new`** | Start a fresh Pi session in the current directory. |
| **`/skill:handoff`** | Write a portable Markdown file that can seed a session anywhere. |
| **Subagent** | Run a bounded AFK task through `pi-subagents` and return its report or supported worktree handoff. Ticket-workers own managed worktrees; nested reviewers inherit that cwd with `worktree: false`. |
| **`/split-fork`** | Open an interactive fork in another terminal pane, tab, or window. |
| **`/compact`** | Compress this session's context and continue from the summary. |

## The tree

Work top to bottom at the boundary. The first **yes** wins.

**1. Can you continue in this session?** Two things make the answer yes: the next phase needs this phase as a **primary source**, or you have enough [smart zone](https://www.aihero.dev/ai-coding-dictionary/smart-zone) left (about 150k tokens) for the next phase to fit. Grilling to implementation is the standard yes: the implementation wants the reasoning verbatim, not a summary of it. Continue costs nothing and loses nothing, so rule it out before anything else.

**2. Is the context irrelevant to what comes next?** Is everything in this session (the exploration, decisions, and dead ends) disposable? If so, use **`/new`**. The old session remains resumable, while the new session gets the whole context window.

The cost of getting this wrong is one-way. Start fresh when the context is relevant and you lose the **why** behind what you built; reading the diff cannot restore it.

**3. Does context need to travel?** Use `/skill:handoff` when you are:

- swapping to a new harness,
- moving to a new directory or repository,
- sending the work to a colleague,
- or carrying a side task somewhere that cannot inherit this session.

That list is the whole clause. A handoff buys **portability** through a file. If nothing is travelling, you do not need it.

**4. Can the task run AFK?** If it is tightly scoped and needs no steering, use the Pi `subagent` tool. Automated review, research, and repository reconnaissance are the standard cases. The child has isolated model context but shares the filesystem. Findings agents write only their assigned artifacts. The parent waits for the dispatch to finish.

**5. Does the side task need a human?** Use `/split-fork` when a second interactive Pi should keep the current context branch but needs its own terminal and live steering. Use it for prototypes, exploratory debugging, or another task that cannot run AFK.

**6. Otherwise, `/compact`.** Relevant context, same harness, same directory, and continued human involvement: this is where the tree lands. Pass an instruction such as `/compact we're going to QA this area` so the summary keeps what the next phase needs.

`/compact` is the **default, not the first reach**. It sits at the bottom because the earlier choices are cheaper or more precise. Starting here risks a continued session that is confidently wrong about a decision the summary flattened.

## Primary and secondary sources

Every move except **Continue** replaces some primary context with a secondary view. A subagent receives a scoped brief; a ticket-worker additionally owns one managed Git worktree, while nested read-only reviewers inherit it without creating another. A split fork inherits a branch point but diverges afterward. A handoff and compaction use summaries.

| Source | Information | Noise | Room to move |
| --- | --- | --- | --- |
| Primary (Continue) | Full | Lots | Little |
| Secondary (`/compact`, `/skill:handoff`, delegation) | Scoped or lossy | Less | Lots |

This is why question 1 comes first. Pay the loss only when staying costs more than it saves.

## These are judgement calls

The questions are not objective. The same boundary can go two ways on two days. The value is asking them **in order**, at the boundary rather than in the middle of the work.
