<!-- ph4ge:begin v1 -->
# PH4GE Guidance (managed block)

This block is managed by PH4GE. It tells an agent working in this child
repository how to behave inside a PH4GE-bootstrapped workspace.

## Read this first

1. Locate the workspace-root `PH4GE.md` (the parent directory of this
   repository). It defines the protocol and the safety boundary that
   apply on top of this block.
2. Read any local instructions that belong to this repository. Local
   instructions take priority over workspace-generated material.
3. Use the `/ph4ge` protocol when the host platform exposes it.

## What you must do

- Honor local repository instructions before workspace-generated
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

- Do not edit this repository's `CLAUDE.md` if one exists.
- Do not modify Git history, force-push, or amend published commits.
- Do not install or modify native state for third-party agents such as
  Hermes or OpenClaw unless the user explicitly asks.

## Limits

- PH4GE inspects only the immediate children of the workspace root. It
  does not recurse and does not follow symlinks.
- The installer rejects a filesystem root, a home directory, a missing
  folder, and a workspace with no immediate child Git repositories.
<!-- ph4ge:end -->
