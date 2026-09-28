[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$WorkspaceRoot
)

# ph4ge:managed-file v1
# Installs PH4GE only into an explicit workspace root. It never changes source
# files, Git history, existing root documents, settings, or child CLAUDE files.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BeginMarker = '<!-- ph4ge:begin v1 -->'
$EndMarker = '<!-- ph4ge:end -->'
$KitRoot = Join-Path -Path $PSScriptRoot -ChildPath 'kit'

function Get-NormalPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
}

function Test-SamePath {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    return [string]::Equals((Get-NormalPath $Left), (Get-NormalPath $Right),
        [System.StringComparison]::OrdinalIgnoreCase)
}

function Resolve-WorkspaceRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Workspace root must be an existing directory: $Path"
    }

    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Workspace root must not be a symbolic link or reparse point: $($item.FullName)"
    }

    $full = Get-NormalPath $item.FullName
    $driveRoot = [System.IO.Path]::GetPathRoot($item.FullName).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    if ([string]::Equals($full, $driveRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate on a filesystem root: $($item.FullName)"
    }

    $homeCandidates = @($env:USERPROFILE, $env:HOME,
        [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Container) }
    foreach ($homeDirectory in $homeCandidates) {
        if (Test-SamePath -Left $item.FullName -Right $homeDirectory) {
            throw "Refusing to operate on a home directory: $($item.FullName)"
        }
    }

    return $item.FullName
}

function Get-ImmediateChildRepositories {
    param([Parameter(Mandatory = $true)][string]$Root)

    $repositories = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]
    foreach ($child in Get-ChildItem -LiteralPath $Root -Force -Directory) {
        if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Write-Host "Plan: skip reparse-point child $($child.FullName)"
            continue
        }

        $gitPath = Join-Path -Path $child.FullName -ChildPath '.git'
        if ((Test-Path -LiteralPath $gitPath -PathType Container) -or
            (Test-Path -LiteralPath $gitPath -PathType Leaf)) {
            $repositories.Add($child) | Out-Null
        }
    }
    return $repositories
}

function Get-SafeTextFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    [byte[]]$bytes = [System.IO.File]::ReadAllBytes($Path)
    $offset = 0
    $encoding = $null

    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $encoding = New-Object System.Text.UTF8Encoding($true, $true)
        $offset = 3
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $encoding = New-Object System.Text.UnicodeEncoding($false, $true, $true)
        $offset = 2
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $encoding = New-Object System.Text.UnicodeEncoding($true, $true, $true)
        $offset = 2
    } else {
        $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    }

    try {
        $text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    } catch {
        throw "Cannot safely preserve the encoding of $Path. Use UTF-8 or UTF-16."
    }

    $newline = if ($text.Contains("`r`n")) { "`r`n" } elseif ($text.Contains("`n")) { "`n" } elseif ($text.Contains("`r")) { "`r" } else { [Environment]::NewLine }
    return [pscustomobject]@{ Text = $text; Encoding = $encoding; Newline = $newline }
}

function Convert-Newlines {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Newline
    )

    return [regex]::Replace($Text, "`r`n|`n|`r", [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $Newline })
}

function Test-Ph4geManagedSupportFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $sample = [System.IO.File]::ReadAllText($Path)
    } catch {
        return $false
    }
    return $sample.StartsWith('# ph4ge:managed-file v1') -or
        $sample.StartsWith('<!-- ph4ge:begin v1 -->')
}

function New-ChildAgentAction {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$TemplatePath
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        $templateSource = $TemplatePath
        $operation = {
            param($destination)
            $directory = Split-Path -Parent $destination
            [System.IO.Directory]::CreateDirectory($directory) | Out-Null
            [System.IO.File]::Copy($templateSource, $destination, $false)
        }.GetNewClosure()
        return [pscustomobject]@{
            Path = $Path; Description = 'create child AGENTS.md from PH4GE template'
            Execute = $operation
        }
    }

    $file = Get-SafeTextFile -Path $Path
    $beginCount = [regex]::Matches($file.Text, [regex]::Escape($BeginMarker)).Count
    $endCount = [regex]::Matches($file.Text, [regex]::Escape($EndMarker)).Count
    if ($beginCount -eq 0 -and $endCount -eq 0) {
        $block = Convert-Newlines -Text (Get-SafeTextFile -Path $TemplatePath).Text -Newline $file.Newline
        $separator = if ($file.Text.Length -eq 0 -or $file.Text.EndsWith("`n") -or $file.Text.EndsWith("`r")) { '' } else { $file.Newline }
        $updated = $file.Text + $separator + $block
        $updatedText = $updated
        $writeEncoding = $file.Encoding
        $operation = {
            param($destination)
            [System.IO.File]::WriteAllText($destination, $updatedText, $writeEncoding)
        }.GetNewClosure()
        return [pscustomobject]@{
            Path = $Path; Description = 'append PH4GE managed block to child AGENTS.md'
            Execute = $operation
        }
    }

    if ($beginCount -ne 1 -or $endCount -ne 1) {
        throw "Malformed PH4GE markers in $Path. Both markers must appear exactly once."
    }

    $beginIndex = $file.Text.IndexOf($BeginMarker, [System.StringComparison]::Ordinal)
    $endIndex = $file.Text.IndexOf($EndMarker, [System.StringComparison]::Ordinal)
    if ($beginIndex -gt $endIndex) {
        throw "Malformed PH4GE markers in $Path. The end marker appears before the begin marker."
    }

    $replacement = Convert-Newlines -Text (Get-SafeTextFile -Path $TemplatePath).Text -Newline $file.Newline
    $replacement = $replacement.TrimEnd("`r", "`n")
    $pattern = '(?s)' + [regex]::Escape($BeginMarker) + '.*?' + [regex]::Escape($EndMarker)
    $updated = [regex]::Replace($file.Text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement }, 1)
    $updatedText = $updated
    $writeEncoding = $file.Encoding
    $operation = {
        param($destination)
        [System.IO.File]::WriteAllText($destination, $updatedText, $writeEncoding)
    }.GetNewClosure()
    return [pscustomobject]@{
        Path = $Path; Description = 'refresh PH4GE managed block in child AGENTS.md'
        Execute = $operation
    }
}

function New-CopyAction {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $copySource = $Source
    $operation = {
        param($target)
        [System.IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
        [System.IO.File]::Copy($copySource, $target, $true)
    }.GetNewClosure()
    return [pscustomobject]@{
        Path = $Destination; Description = $Description
        Execute = $operation
    }
}

if (-not (Test-Path -LiteralPath $KitRoot -PathType Container)) {
    throw "PH4GE kit is missing: $KitRoot"
}

$root = Resolve-WorkspaceRoot -Path $WorkspaceRoot
$repositories = @(Get-ImmediateChildRepositories -Root $root)
if ($repositories.Count -eq 0) {
    throw "Workspace root has no immediate child Git repositories: $root"
}

$actions = New-Object System.Collections.Generic.List[object]
$rootFiles = @(
    @{ Source = 'root-AGENTS.md'; Destination = 'AGENTS.md' },
    @{ Source = 'root-CLAUDE.md'; Destination = 'CLAUDE.md' },
    @{ Source = 'root-PH4GE.md'; Destination = 'PH4GE.md' },
    @{ Source = '../.claude/commands/ph4ge.md'; Destination = '.claude/commands/ph4ge.md' }
)
foreach ($entry in $rootFiles) {
    $destination = Join-Path -Path $root -ChildPath $entry.Destination
    if (Test-Path -LiteralPath $destination) {
        Write-Host "Plan: preserve existing root file $destination"
        continue
    }
    $source = if ($entry.Source.StartsWith('../')) {
        Join-Path -Path $KitRoot -ChildPath $entry.Source.Substring(3)
    } else {
        Join-Path -Path $KitRoot -ChildPath (Join-Path '.ph4ge/templates' $entry.Source)
    }
    $actions.Add((New-CopyAction -Source $source -Destination $destination -Description 'create missing root PH4GE file')) | Out-Null
}

$supportRoot = Join-Path -Path $KitRoot -ChildPath '.ph4ge'
foreach ($source in Get-ChildItem -LiteralPath $supportRoot -Recurse -File) {
    $relative = $source.FullName.Substring($supportRoot.Length).TrimStart('\', '/')
    $destination = Join-Path -Path (Join-Path -Path $root -ChildPath '.ph4ge') -ChildPath $relative
    if (-not (Test-Path -LiteralPath $destination)) {
        $actions.Add((New-CopyAction -Source $source.FullName -Destination $destination -Description 'create PH4GE support file')) | Out-Null
    } elseif (Test-Ph4geManagedSupportFile -Path $destination) {
        $actions.Add((New-CopyAction -Source $source.FullName -Destination $destination -Description 'refresh PH4GE-owned support file')) | Out-Null
    } else {
        Write-Host "Plan: preserve non-PH4GE support file $destination"
    }
}

$childTemplate = Join-Path -Path $supportRoot -ChildPath 'templates/child-AGENTS.md'
foreach ($repository in $repositories) {
    $agentPath = Join-Path -Path $repository.FullName -ChildPath 'AGENTS.md'
    $actions.Add((New-ChildAgentAction -Path $agentPath -TemplatePath $childTemplate)) | Out-Null
}

foreach ($action in $actions) {
    Write-Host "Plan: $($action.Description): $($action.Path)"
    if ($PSCmdlet.ShouldProcess($action.Path, $action.Description)) {
        & $action.Execute $action.Path
    }
}

Write-Host "PH4GE processed $($repositories.Count) immediate child Git repository/repositories."
