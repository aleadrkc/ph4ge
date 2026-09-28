# ph4ge:managed-file v1
# Read-only PH4GE workspace map.
# Prints a short human-readable workspace/repository map. Writes nothing.

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

if (-not (Test-Ph4geRootPath -Path $WorkspaceRoot)) {
    exit 2
}

$rootFull = [System.IO.Path]::GetFullPath($WorkspaceRoot)
Write-Output ('Workspace: ' + $rootFull)

$children = Get-ChildItem -LiteralPath $rootFull -Force -Directory
$repoCount = 0
foreach ($entry in $children) {
    $gitDir = Join-Path -Path $entry.FullName -ChildPath '.git'
    if (Test-Path -LiteralPath $gitDir) {
        $repoCount++
        $hasAgents = Test-Path -LiteralPath (Join-Path -Path $entry.FullName -ChildPath 'AGENTS.md')
        $hasClaude = Test-Path -LiteralPath (Join-Path -Path $entry.FullName -ChildPath 'CLAUDE.md')
        $status = 'AGENTS=' + ($(if ($hasAgents) { 'yes' } else { 'no' })) + ' CLAUDE=' + ($(if ($hasClaude) { 'yes' } else { 'no' }))
        Write-Output (' - ' + $entry.Name + ' (' + $status + ')')
    }
}

if ($repoCount -eq 0) {
    Write-Output ' (no immediate child Git repositories)'
}

$hasSettings = Test-Path -LiteralPath (Join-Path -Path $rootFull -ChildPath '.claude/settings.json')
Write-Output ('Settings: ' + ($(if ($hasSettings) { 'present (untouched)' } else { 'absent' })))
