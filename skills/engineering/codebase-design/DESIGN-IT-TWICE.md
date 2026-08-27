# Design It Twice

When the user wants to explore alternative interfaces for a chosen deepening candidate, use isolated Pi designers in parallel. Based on "Design It Twice" (Ousterhout): your first idea is unlikely to be the best.

Uses the vocabulary in [SKILL.md](SKILL.md): **module**, **interface**, **seam**, **adapter**, **leverage**, **locality**.

## Process

### 1. Frame the problem space

Write a user-facing explanation of the chosen candidate:

- The constraints every new interface must satisfy
- The dependencies it relies on and their categories from [DEEPENING.md](DEEPENING.md)
- A rough illustrative code sketch that grounds the constraints without proposing an answer

Show this to the user, then proceed to delegation. The user can read it while the designers run, but the parent Pi waits for the dispatch to finish.

### 2. Allocate design artifacts

Capture `git status --short`. Create a unique run directory at `.scratch/pi-agents/design-it-twice-<timestamp>/` with one artifact per design:

```text
design-minimal-interface.md
design-locality.md
design-testability.md
```

Add `design-ports-and-adapters.md` when the candidate crosses a process, network, storage, or third-party seam.

### 3. Delegate independent designs

Invoke the Pi `subagent` tool with `async: false` and a `workflowScript` using `await runs.all([...])`. Use agent `interface-designer` for every child with `context: "fresh"` and `worktree: false`, plus a separate technical brief and exact artifact path. Each brief includes relevant file paths, coupling details, dependency category, what sits behind the seam, [SKILL.md](SKILL.md) vocabulary, and the project's `CONTEXT.md` vocabulary.

Give each designer one constraint:

1. **Minimal interface**: aim for one to three entry points and maximize leverage per entry point.
2. **Locality**: concentrate knowledge and likely change inside the module, even when that costs a slightly wider interface.
3. **Testability**: make important behavior observable through the interface with the fewest test seams and adapters.
4. **Ports and adapters**, when applicable: isolate cross-seam dependencies behind explicit ports and concrete adapters.

A designer must not read another design artifact. Every design must contain:

1. Interface types, methods, parameters, invariants, ordering, and error modes
2. A caller example
3. Behavior hidden behind the seam
4. Dependency and adapter strategy
5. Test surface
6. Tradeoffs in depth, leverage, locality, and seam placement

After delegation, compare `git status --short` with the captured state. The only new paths attributable to designers must be their assigned artifacts. Stop and report any unexpected change.

If the `subagent` tool is unavailable, produce the designs in separate sequential passes, write the same artifacts, and disclose that they were not context-isolated.

### 4. Present and compare

Read and present the designs sequentially so the user can absorb each one. Compare them in prose by **depth**, **locality**, **leverage**, **testability**, and **seam placement**.

Give a recommendation. If elements combine well, propose a concrete hybrid. Be opinionated: the user wants a strong read, not a menu.
