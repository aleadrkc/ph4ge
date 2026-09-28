# PH4GE Protocol

PH4GE is a safe, opt-in bootstrap for a workspace root that contains one
or more immediate child Git repositories. It installs generic workspace
agent guidance and one managed block into each immediate child repo
`AGENTS.md`. The name is inspired by controlled instruction injection,
not stealth.

## Scope

PH4GE only inspects the immediate children of the workspace root. It does
not recurse into grandchildren and does not follow symlinks.

## What PH4GE installs

In the workspace root, only when a file is absent:

- `AGENTS.md` — universal guidance for any agent.
- `CLAUDE.md` — short pointer for Claude.
- `PH4GE.md` — this protocol file.
- `.claude/commands/ph4ge.md` — the `/ph4ge` slash command.
- `.ph4ge/` — PH4GE-owned support files (scripts and templates).

In every immediate child Git repository:

- If `AGENTS.md` is absent, create it from the child template.
- If `AGENTS.md` exists and contains no managed markers, insert the
  managed block once at the end of the file.
- If `AGENTS.md` contains both the begin and end markers, replace only
  the managed block between them.
- If the markers are malformed or mismatched, stop and report.

## What PH4GE never touches

- Source code.
- Git history.
- Credentials, secrets, tokens, and keys.
- Unmarked agent content.
- An existing `.claude/settings.json`.
- A child `CLAUDE.md`.

## Safety boundary

- The installer requires an explicit workspace path.
- The installer rejects a filesystem root, a home directory, a missing
  folder, and a workspace with no immediate child Git repositories.
- The installer prints every planned change before writing.
- The PowerShell installer honors `-WhatIf`.
- The Bash installer honors `--dry-run`.
- The Bash installer accepts UTF-8 input only and rejects UTF-16 or
  BOM-prefixed files.
- PH4GE never makes external changes. It does not push, publish, deploy,
  or share data.

## Managed block markers

The child `AGENTS.md` template uses these exact markers:

```
<!-- ph4ge:begin v1 -->
...
<!-- ph4ge:end -->
```

Root documents owned by the user are not marked. PH4GE-owned support
files carry the marker `# ph4ge:managed-file v1` (or the equivalent in
the file's own comment style).

## Repeat runs

Both installers are idempotent. Re-running the installer on a workspace
that PH4GE already bootstrapped must not change user-owned content.