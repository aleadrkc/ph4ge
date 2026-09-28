# Workspace Agent Guidance

This file is the universal workspace-level guidance for any agent working
inside this workspace. It is intentionally generic. Local repository
instructions always take priority over this file.

## Read this first

1. Read `PH4GE.md` in the workspace root. It defines the protocol and the
   safety boundary that apply on top of this file.
2. Read any local repository instructions for the child repo you are about
   to touch. Local instructions win over workspace-generated material.
3. Use the `/ph4ge` protocol if your host platform exposes it.

## What you must do

- Honor local repository instructions before any workspace-generated
  material.
- Preserve user-owned content. During PH4GE bootstrap or repair, never
  edit source code, Git history, credentials, or unmarked agent content.
- For a normal user-authorized project task after bootstrap, follow the
  local repository instructions and the stated task scope.
- Make no external changes by default. Do not push, publish, deploy, or
  share data outside the local environment without explicit user
  approval.
- Never expose secrets. If you see a secret in a file, stop and tell the
  user.
- Never commit, deploy, or push without explicit user approval.

## What you must not do

- Do not edit a child `CLAUDE.md`. The installer will not change it, and
  neither should you.
- Do not edit an existing `.claude/settings.json`.
- Do not modify Git history, force-push, or amend published commits.
- Do not install or modify native state for third-party agents such as
  Hermes or OpenClaw unless the user explicitly asks.

## Limits

- PH4GE inspects only immediate child directories of the workspace root.
  It does not recurse and does not follow symlinks.
- The installer rejects a filesystem root, a home directory, a missing
  folder, and a workspace with no immediate child Git repositories.
