---
description: Inspect a PH4GE-bootstrapped workspace and report status.
---

# /ph4ge

Read the workspace-root `AGENTS.md` and `PH4GE.md` before doing anything
else. Local repository instructions take priority.

## Steps

1. Invoke the platform-appropriate read-only helper from `.ph4ge/scripts/`:
   - On Windows PowerShell: `powershell.exe -NoProfile -File .ph4ge/scripts/ph4ge-probe.ps1 -WorkspaceRoot .`
   - On Linux/macOS: `.ph4ge/scripts/ph4ge-probe.sh --workspace .`
2. Run the map helper on the same workspace root:
   - On Windows PowerShell: `powershell.exe -NoProfile -File .ph4ge/scripts/ph4ge-map.ps1 -WorkspaceRoot .`
   - On Linux/macOS: `.ph4ge/scripts/ph4ge-map.sh --workspace .`
3. Report the workspace map and the safety status that the helpers print.
4. If the helpers report a problem, ask the user before repairing. Repair
   means re-running the installer. Never edit repositories directly.

## What this command never does

- It does not install or modify repositories on its own.
- It does not edit a child `CLAUDE.md` or an existing `.claude/settings.json`.
- It does not push, publish, deploy, or share data.
