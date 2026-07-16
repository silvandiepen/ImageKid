# Git & Commit Conventions

## Permission

- Never run `git commit` or `git push` unless the user explicitly asks for it in the current
  turn (e.g. "commit this", "push", "deploy"). Doing work and stopping to let the user review
  is the default; committing is not implied by "looks good" or silence.
- Never force-push, never skip hooks (`--no-verify`), never amend a commit that isn't the one
  you just created in this session, unless explicitly told to.

## Commit messages

Conventional Commits, always: `type(scope): short imperative subject`

Types in use: `feat, fix, chore, refactor, style, docs, test, release`.
Scope is typically the affected app, module, or component name (e.g. `feat(Header): ...`,
`fix(worker): ...`, `chore(release): ...`).

Rules:
- **Never** include a `Co-Authored-By: Claude` (or any AI) trailer. This is a hard, repeated
  rule across every repo it was checked in — no exceptions, no matter what default commit
  templates suggest.
- Subject is short and imperative ("Add track artwork step", not "Added" or "Adding").
- Group commits by feature/concern — atomic commits, not "fix stuff" / "update code" / "WIP".
- Commit body (when present) explains *why*, not what — commits are sometimes used to
  generate release notes / changelogs (see `ui`'s semantic-release setup), so write for that
  audience.

## Branching

- `main` (or `master`) is production/release-only in multi-branch repos; `development` is the
  integration branch. Feature work branches off `development`, not `main`, in repos that use
  this model (seen in `mikki`). Smaller/solo repos may just use `main` directly — check
  existing branch structure before assuming.
- Greenfield/actively-developed repos generally don't need to preserve backwards compatibility
  or legacy routes for their own sake — prefer the clean current shape over compat shims,
  unless the project has real external consumers.

## Task tracking

Some repos (e.g. `lezu-platform`) require every non-trivial task to have a matching GitHub
issue, created or updated as work progresses. Not universal — adopt it for projects that
already use GitHub Issues as their task tracker, otherwise don't invent process that isn't there.
