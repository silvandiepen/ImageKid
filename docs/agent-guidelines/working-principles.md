# Working Principles

How to behave as an agent working in one of Sil's repos, independent of stack.

## Fix root causes, don't paper over

- Never mock in place of a real implementation. If something can't be implemented for real
  right now, say so — don't fake it silently.
- Do not work around errors: don't remove imports, silently catch-and-ignore exceptions, add
  `// @ts-ignore`/`eslint-disable`, or delete a failing test/check to make things pass. Find
  and fix the actual cause. If a dependency is missing, install it — don't remove the import
  that needs it.
- If you notice a check is disabled or a workaround already exists in the code, that's worth
  flagging, not silently building on top of.

## Reuse before you build

Before adding a new component, composable, utility, or package dependency, check whether the
codebase already has something that solves the problem. Extend/reuse existing patterns
instead of creating a second, parallel implementation of the same thing.

## Clean as you go, don't over-clean

When you touch a file for an unrelated reason, it's fine (encouraged) to remove dead/unused
code in that file as long as it's safe and clearly in scope. It is not an invitation to
refactor everything nearby — match the change to what was actually asked.

## Priority order when trade-offs conflict

Security/privacy > architecture clarity > maintainability > extensibility > developer
convenience. Avoid premature complexity; don't design for hypothetical future requirements
that haven't been asked for.

## Secrets

Never commit secrets, real `.env` files, certificates, private keys, or tokens. Treat any
file that looks like it might contain one with extra scrutiny before staging/committing.

## Greenfield vs legacy

In actively-developed, greenfield-leaning projects, prefer the clean current shape of the
product over preserving backwards compatibility or legacy routes — don't invent compat shims
nobody asked for. This does not apply to packages/projects with real external consumers.
