# AGENTS.md

This file defines the working rules for every coding agent operating in this repository. Follow these instructions for all files and subdirectories unless a more specific `AGENTS.md` exists deeper in the tree.

## Absolute Git Safety Rule

Never change Git state in this repository.

- Never run `git init`, `git add`, `git commit`, `git push`, or any equivalent command.
- Never stage, commit, push, fetch, pull, merge, rebase, cherry-pick, revert, tag, stash, switch, checkout, reset, restore, clean, or modify branches, remotes, hooks, configuration, the index, refs, or history.
- Never create a repository, initialize a worktree, force-push, or open/update a pull request.
- Never use a Git library, IDE integration, hosting API, or other tool to perform an action that would be forbidden at the command line.
- Do not modify anything inside `.git/`.
- Read-only inspection such as `git status`, `git diff`, `git log`, and `git show` is allowed only when useful, but it must not change repository state.
- Leave all version-control actions to the user. When work is complete, report the files changed and the checks run; do not prepare or publish a commit.

This rule is unconditional. A task is not complete if it requires violating it; instead, explain that the user must perform the Git step themselves.

## Core Working Principles

- Understand the relevant code, configuration, tests, and documentation before editing.
- Make the smallest coherent change that fully solves the request.
- Preserve existing behavior and public interfaces unless the task explicitly requires a breaking change.
- Follow the repository's established architecture, naming, formatting, and dependency patterns.
- Prefer clear, maintainable code over clever abstractions or premature optimization.
- Keep unrelated refactors, formatting churn, and generated-file changes out of the task.
- Preserve user changes. Never overwrite, delete, or undo work that is outside the requested scope.
- State assumptions when requirements are ambiguous, and ask before making a choice with significant product, data, security, or compatibility impact.

## Before Editing

1. Read the nearest applicable `AGENTS.md` and relevant project documentation.
2. Inspect the files involved and search for related implementations, tests, types, and call sites.
3. Identify existing build, lint, format, test, and type-check commands from project configuration.
4. Check for local modifications using non-mutating inspection when useful, and avoid disturbing them.
5. Plan for compatibility, validation, error handling, security, accessibility, and tests appropriate to the change.

## Implementation Standards

- Use descriptive names and small, focused functions and modules.
- Keep business logic separate from transport, UI, persistence, and framework glue when practical.
- Avoid duplicated logic; reuse a local abstraction when it is genuinely shared and stable.
- Prefer explicit data flow and dependency injection over hidden global state.
- Use strong types and narrow interfaces where the language supports them. Avoid untyped escape hatches unless unavoidable and documented.
- Validate data at trust boundaries, including user input, network responses, files, environment variables, and database records.
- Handle expected failures deliberately. Do not swallow exceptions or return misleading success states.
- Make operations idempotent when they may be retried.
- Consider concurrency, cancellation, timeouts, resource cleanup, and partial failure for I/O or asynchronous work.
- Use structured logging where available. Log actionable context, but never secrets or unnecessary personal data.
- Comment why a non-obvious decision exists, not what straightforward code already says.
- Remove dead code, debugging statements, placeholder hacks, and commented-out implementations introduced during the task.
- Do not hand-edit generated artifacts unless the project explicitly treats them as source files.

## Security and Privacy

- Never hard-code, print, expose, or commit secrets, credentials, tokens, private keys, or sensitive user data.
- Store local secrets in ignored environment files or the project's approved secret manager.
- Provide sanitized examples through files such as `.env.example`; use placeholders, never real values.
- Apply least privilege to permissions, credentials, network access, and data access.
- Use parameterized queries and safe framework APIs. Prevent injection, path traversal, unsafe deserialization, SSRF, XSS, CSRF, and authorization bypasses as relevant.
- Authenticate and authorize on trusted server-side boundaries; never rely solely on client-side checks.
- Avoid adding dependencies for functionality that can be implemented safely and simply with existing tools.
- If a dependency is necessary, prefer maintained, reputable packages and keep the project's lockfile updated through its package manager.
- Do not weaken security controls, certificate validation, type checks, lint rules, or tests merely to make a change pass.

## Testing and Verification

- Add or update tests for new behavior, bug fixes, important branches, and regressions when a test framework exists.
- Prefer deterministic tests that do not depend on real external services, wall-clock timing, random state, or execution order.
- Test observable behavior rather than private implementation details.
- Include edge cases and failure paths, not only the happy path.
- Run the narrowest relevant checks first, then broader checks when practical: formatting, linting, type checking, unit tests, integration tests, and build.
- Do not claim a check passed unless it was actually run successfully.
- If a check cannot run, report the exact command, failure, and likely reason. Do not hide failures or disable checks.
- Never change production behavior solely to accommodate a weak test; improve the test or design instead.

## Frontend and UX

- Use semantic HTML and accessible controls with keyboard support, visible focus states, labels, and appropriate ARIA only when native semantics are insufficient.
- Maintain responsive behavior across common viewport sizes.
- Respect reduced-motion preferences, adequate contrast, and existing design tokens/components.
- Represent loading, empty, error, success, disabled, and partial-data states where applicable.
- Avoid unnecessary client work, layout shifts, oversized assets, and inaccessible custom widgets.

## APIs, Data, and Migrations

- Keep APIs backward compatible unless a breaking change is explicitly approved.
- Use consistent schemas, status codes, error shapes, pagination, and validation.
- Treat database migrations as production-sensitive: make them reversible when practical, safe for existing data, and compatible with staged deployments.
- Avoid destructive data operations without explicit user authorization and a verified recovery plan.
- Do not silently change data formats, identifiers, time-zone behavior, or numeric precision.

## Dependencies and Generated Files

- Use the package manager and lockfile already selected by the project; do not introduce a second package manager.
- Do not delete, replace, or regenerate a lockfile casually.
- Keep dependency additions minimal and explain any non-obvious choice.
- Do not modify vendored code, build output, coverage output, caches, or generated files unless the task specifically requires it.
- Keep machine-specific configuration and secrets out of source files.

## Documentation

- Update relevant README, API, configuration, migration, or operational documentation when behavior or setup changes.
- Keep examples runnable and consistent with the code.
- Document new environment variables in `.env.example` or the project's established configuration reference.
- Record meaningful compatibility concerns, limitations, and migration steps.

## Final Handoff

At the end of a task:

- Summarize what changed and why.
- List the validation commands actually run and their results.
- Call out unresolved risks, assumptions, or checks that could not be completed.
- Identify any manual steps the user must perform.
- Do not stage, commit, push, or otherwise publish the work.

