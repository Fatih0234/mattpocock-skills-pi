# Model-invoked vs user-invoked

Every `SKILL.md` in this repo is a skill. The one axis that splits them is **invocation**, who can reach it:

- **User-invoked**: reachable **only by the human typing its name**. Set `disable-model-invocation: true` in the frontmatter (Claude Code) and `policy.allow_implicit_invocation: false` in `agents/openai.yaml` (Codex). The `description` is **human-facing**: a one-line summary read by a person browsing slash-commands. Strip trigger lists ("Use when the user says…").
- **Model-invoked**: reachable by **model or user**. The default: omit `disable-model-invocation` and the `policy` block from `agents/openai.yaml`. The `description` is **model-facing** and keeps rich trigger phrasing ("Use when the user wants…, mentions…, asks for…") so auto-invocation fires. The test for whether a skill should stay model-invoked: _could the model usefully reach for this autonomously?_ (Reuse is the reason to extract a skill, not the test.)

Each harness excludes a user-invoked skill from the model's reach in its own way, so nothing but the human can fire it: no other skill can. A user-invoked skill may invoke model-invoked skills, but it can never reach another user-invoked skill.

Every skill also carries an `agents/openai.yaml` beside its `SKILL.md`. It holds Codex UI metadata: `interface.display_name` and `interface.short_description` for the skill picker, and, for user-invoked skills, the `policy.allow_implicit_invocation: false` that pairs with `disable-model-invocation`. Keep the two in sync: a skill is user-invoked in both harnesses or neither.

Bucket `README.md`s and the top-level `README.md` group entries into **User-invoked** and **Model-invoked**.

## Dependencies between them

This Pi integration has no separate Skill tool. An operative dependency is expressed as **load and follow the named skill**. Pi advertises each available skill with its `SKILL.md` path, and the agent uses `read` to load that file before following it. Do not use deep `../other-skill/FILE.md` cross-references: shared reference lives inside the skill that owns it, and another skill reaches that material by loading the owner.

This is about **operative** instructions: a skill's own steps telling the agent to apply another skill now. Router prose that names skills for a human to pick from (`ask-matt`, bucket `README.md`s) is not invoking anything, so it uses Pi's user-facing `/skill:<name>` labels.

A step that needs two model-invoked skills says to load and follow both, naming each explicitly. Loading does not create a new context boundary; both instruction sets run in the current parent session unless the skill explicitly invokes the Pi `subagent` tool.

This convention only holds when the named skill is **model-invoked**. A user-invoked skill remains reachable only by the human. When a step's precondition is user-invoked (for example `setup-matt-pocock-skills`), tell the user to run `/skill:setup-matt-pocock-skills` rather than trying to load it as an operative dependency.

## Passive vs active domain work

Merely _reading_ `CONTEXT.md` for vocabulary is a one-line prose pointer, not the `domain-modeling` skill. Only the active build/sharpen discipline (challenge terms, edge-case scenarios, write ADRs, update `CONTEXT.md` inline) is `domain-modeling`.
