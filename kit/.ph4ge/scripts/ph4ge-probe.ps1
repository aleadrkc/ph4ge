# ph4ge:managed-file v1
# Read-only PH4GE workspace probe.
# Verifies the expected root support material and discovers immediate
# child Git repositories. Writes nothing.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceRoot
)

$ErrorActionPreference = 'Stop'

function Test-Ph4geRootPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Error "Workspace path does not exist: $Path"
        return $false
    }

    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSProvider.Name -ne 'FileSystem') {
        Write-Error "Workspace path is not on the filesystem: $Path"
        return $false
    }

    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($full)
    if ([string]::Equals($full, $root, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Error "Refusing to operate on a filesystem root: $full"
        return $false
    }

    $home = $env:USERPROFILE
    if (-not $home) { $home = $env:HOME }
    if ($home) {
        $homeFull = [System.IO.Path]::GetFullPath($home)
        if ([string]::Equals($full, $homeFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Error "Refusing to operate on a home directory: $full"
            return $false
        }
    }

    return $true
}

function Get-Ph4geImmediateChildRepos {
    param([Parameter(Mandatory = $true)][string]$Root)

    $found = New-Object System.Collections.Generic.List[string]
    $entries = Get-ChildItem -LiteralPath $Root -Force -Directory
    foreach ($entry in $entries) {
        $gitDir = Join-Path -Path $entry.FullName -ChildPath '.git'
        if (Test-Path -LiteralPath $gitDir) {
            $found.Add($entry.Name) | Out-Null
        }
    }
    return $found
}

if (-not (Test-Ph4geRootPath -Path $WorkspaceRoot)) {
    exit 2
}

$rootFull = [System.IO.Path]::GetFullPath($WorkspaceRoot)

$expected = @(
    'AGENTS.md',
    'CLAUDE.md',
    'PH4GE.md',
    '.claude/commands/ph4ge.md',
    '.ph4ge/scripts/ph4ge-probe.ps1',
    '.ph4ge/scripts/ph4ge-map.ps1',
    '.ph4ge/scripts/ph4ge-probe.sh',
    '.ph4ge/scripts/ph4ge-map.sh',
    '.ph4ge/templates/child-AGENTS.md'
)

$missing = @()
foreach ($rel in $expected) {
    $abs = Join-Path -Path $rootFull -ChildPath $rel
    if (-not (Test-Path -LiteralPath $abs)) {
        $missing += $rel
    }
}

$children = Get-Ph4geImmediateChildRepos -Root $rootFull

Write-Output ('Workspace: ' + $rootFull)
Write-Output ('Root support files missing: ' + ($(if ($missing.Count -eq 0) { 'none' } else { ($missing -join ', ') })))
Write-Output ('Immediate child Git repos: ' + ($(if ($children.Count -eq 0) { 'none' } else { ($children -join ', ') })))

if (Test-Path -LiteralPath (Join-Path -Path $rootFull -ChildPath '.claude/settings.json')) {
    Write-Output ('Settings note: .claude/settings.json exists and was left untouched')
}

if ($missing.Count -gt 0 -or $children.Count -eq 0) {
    exit 1
}
exit 0
