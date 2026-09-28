# PH4GE

PH4GE is a safe, opt-in bootstrap for a workspace root that contains one or
more immediate child Git repositories. It installs generic workspace agent
guidance and a clearly marked instruction block into every immediate child
repo `AGENTS.md`. The name is inspired by controlled instruction injection,
not stealth.

PH4GE never edits source code, Git history, credentials, unmarked agent
content, an existing `.claude/settings.json`, or a child `CLAUDE.md`.

## What it installs

In a target workspace root (only when files are absent):

- `AGENTS.md` — universal root guidance for any agent.
- `CLAUDE.md` — short pointer to `AGENTS.md` and `PH4GE.md` for Claude.
- `PH4GE.md` — the protocol definition and safety boundary.
- `.claude/commands/ph4ge.md` — the `/ph4ge` slash command.
- `.ph4ge/` — PH4GE-owned support files (scripts and templates).

In every immediate child Git repository, only when `AGENTS.md` is absent:

- a new `AGENTS.md` containing the child template.

If a child `AGENTS.md` already exists, PH4GE inserts one managed block
between stable markers, leaving all other text untouched.

## Requirements

- PowerShell 5.1+ on Windows, or Bash 4+ with `iconv` on Linux/macOS.
- A workspace root that contains at least one immediate child Git repository.
- `git` available on `PATH`.

## Installation (PowerShell)

```powershell
./install.ps1 -WorkspaceRoot <path-to-workspace>
```

Dry run, no changes:

```powershell
./install.ps1 -WorkspaceRoot <path-to-workspace> -WhatIf
```

## Installation (Bash)

```bash
bash ./install.sh --workspace <path-to-workspace>
```

Dry run, no changes:

```bash
bash ./install.sh --workspace <path-to-workspace> --dry-run
```

The Bash installer accepts UTF-8 input only. Files encoded in UTF-16 or
starting with a BOM are rejected with a clear error.

## Repeat runs

Both installers are idempotent. Root documents are only created when absent.
Child `AGENTS.md` files are created when absent, or patched between stable
markers when the markers are present. Existing root documents, an existing
`.claude/settings.json`, and a child `CLAUDE.md` are never overwritten.

## How Claude invokes /ph4ge

Inside the workspace, Claude can run the `/ph4ge` slash command. The command
asks Claude to read the root `AGENTS.md` and `PH4GE.md`, invoke the
platform-appropriate read-only helper (`ph4ge-probe` and `ph4ge-map`),
report the workspace map and safety status, and repair the installation
only after asking you. The slash command does not install or edit
repositories on its own.

## How other agents use AGENTS.md / PH4GE.md

Any agent can read the workspace-root `AGENTS.md` and `PH4GE.md`. The root
`AGENTS.md` tells the agent to honor local repository instructions before
workspace-generated material, use the `/ph4ge` protocol when available,
preserve user-owned content, make no external changes by default, never
expose secrets, and never commit, push, or deploy without explicit
approval. A child `AGENTS.md` points the agent at the workspace
`PH4GE.md` and applies the same local-first rule inside that child.

## Limits

- PH4GE only inspects the immediate children of the workspace root. It does
  not recurse and does not follow symlinks.
- The installer rejects a filesystem root, a home directory, a nonexistent
  folder, and a workspace with no immediate child Git repositories.
- PH4GE never edits `CLAUDE.md` in a child repo.
- PH4GE never touches an existing `.claude/settings.json`.
- The Bash installer only accepts UTF-8 input. The PowerShell installer
  preserves detected encoding and stops if a file cannot be read safely.

## Integrations

Hermes and OpenClaw can read and use `AGENTS.md` like any other agent.
PH4GE v0.1 deliberately does not install or change their native state or
configuration files.

## Tests

Run the installer test on PowerShell:

```powershell
./tests/test-install.ps1
```

The test creates temporary fixture workspaces, runs the installer, and
verifies the installed files, idempotence, and that user-owned content is
preserved. It cleans up its own temporary directory.

## First public release

After reviewing the local repository, its maintainer can run:

```powershell
.\publish-public.ps1 -GitHubOwner <account>
```

The script creates `<account>/ph4ge` as a public GitHub repository only when
`origin` is absent, then stages, commits, and pushes `main`. It refuses to
replace an existing unexpected `origin` and never force-pushes. Use `-WhatIf`
to inspect the planned mutating actions first.
