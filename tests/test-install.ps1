# ph4ge:managed-file v1
# Local, dependency-free validation for the PowerShell installer.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path -Path $repositoryRoot -ChildPath 'install.ps1'
$temporaryRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('ph4ge-test-' + [guid]::NewGuid().ToString('N'))

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "Test failed: $Message"
    }
}

function Get-FileDigest {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Initialize-TestRepository {
    param([Parameter(Mandatory = $true)][string]$Path)

    New-Item -ItemType Directory -Path $Path | Out-Null
    & git -C $Path init -q
    if ($LASTEXITCODE -ne 0) {
        throw "Could not initialise local Git fixture: $Path"
    }
}

function Get-TreeDigests {
    param([Parameter(Mandatory = $true)][string]$Root)

    return @(Get-ChildItem -LiteralPath $Root -Recurse -File |
        Sort-Object FullName |
        ForEach-Object {
            [pscustomobject]@{
                RelativePath = $_.FullName.Substring($Root.Length).TrimStart('\', '/')
                Digest = Get-FileDigest -Path $_.FullName
            }
        })
}

try {
    Assert-True -Condition (Test-Path -LiteralPath $installer -PathType Leaf) -Message 'installer is present'
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

    $singleWorkspace = Join-Path -Path $temporaryRoot -ChildPath 'single-workspace'
    $singleRepository = Join-Path -Path $singleWorkspace -ChildPath 'one-repository'
    New-Item -ItemType Directory -Path $singleWorkspace | Out-Null
    Initialize-TestRepository -Path $singleRepository

    $legacyAgent = Join-Path -Path $singleRepository -ChildPath 'AGENTS.md'
    $legacyText = "# Existing guidance`r`nKeep this line exactly."
    [System.IO.File]::WriteAllText($legacyAgent, $legacyText, (New-Object System.Text.UTF8Encoding($true)))
    $childClaude = Join-Path -Path $singleRepository -ChildPath 'CLAUDE.md'
    [System.IO.File]::WriteAllText($childClaude, 'Child-owned Claude guidance.', (New-Object System.Text.UTF8Encoding($false)))
    $childClaudeBefore = Get-FileDigest -Path $childClaude

    $settingsDirectory = Join-Path -Path $singleWorkspace -ChildPath '.claude'
    New-Item -ItemType Directory -Path $settingsDirectory | Out-Null
    $settings = Join-Path -Path $settingsDirectory -ChildPath 'settings.json'
    [System.IO.File]::WriteAllText($settings, '{"keep":"unchanged"}', (New-Object System.Text.UTF8Encoding($false)))
    $settingsBefore = Get-FileDigest -Path $settings

    & $installer -WorkspaceRoot $singleWorkspace
    if ($LASTEXITCODE -ne 0) { throw 'Installer returned a failure for the single-repository fixture.' }

    foreach ($relativePath in @(
        'AGENTS.md', 'CLAUDE.md', 'PH4GE.md', '.claude/commands/ph4ge.md',
        '.ph4ge/scripts/ph4ge-probe.ps1', '.ph4ge/scripts/ph4ge-map.ps1',
        '.ph4ge/scripts/ph4ge-probe.sh', '.ph4ge/scripts/ph4ge-map.sh',
        '.ph4ge/templates/child-AGENTS.md'
    )) {
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path -Path $singleWorkspace -ChildPath $relativePath)) -Message "installed $relativePath"
    }

    $patchedAgent = [System.IO.File]::ReadAllText($legacyAgent)
    Assert-True -Condition $patchedAgent.Contains($legacyText) -Message 'legacy child AGENTS.md text remains'
    Assert-True -Condition $patchedAgent.Contains('<!-- ph4ge:begin v1 -->') -Message 'child begin marker exists'
    Assert-True -Condition $patchedAgent.Contains('<!-- ph4ge:end -->') -Message 'child end marker exists'
    Assert-True -Condition ((Get-FileDigest -Path $settings) -eq $settingsBefore) -Message 'existing settings.json is unchanged'
    Assert-True -Condition ((Get-FileDigest -Path $childClaude) -eq $childClaudeBefore) -Message 'child CLAUDE.md is unchanged'

    $singleBeforeRerun = Get-TreeDigests -Root $singleWorkspace
    & $installer -WorkspaceRoot $singleWorkspace
    if ($LASTEXITCODE -ne 0) { throw 'Installer returned a failure during its idempotence run.' }
    $singleAfterRerun = Get-TreeDigests -Root $singleWorkspace
    Assert-True -Condition (($singleBeforeRerun | ConvertTo-Json -Compress) -eq ($singleAfterRerun | ConvertTo-Json -Compress)) -Message 'second installation is byte-identical'

    $multiWorkspace = Join-Path -Path $temporaryRoot -ChildPath 'multi-workspace'
    New-Item -ItemType Directory -Path $multiWorkspace | Out-Null
    $firstRepository = Join-Path -Path $multiWorkspace -ChildPath 'first-repository'
    $secondRepository = Join-Path -Path $multiWorkspace -ChildPath 'second-repository'
    Initialize-TestRepository -Path $firstRepository
    Initialize-TestRepository -Path $secondRepository
    [System.IO.File]::WriteAllText((Join-Path -Path $secondRepository -ChildPath 'AGENTS.md'), 'Second legacy guidance.', (New-Object System.Text.UTF8Encoding($false)))

    & $installer -WorkspaceRoot $multiWorkspace
    if ($LASTEXITCODE -ne 0) { throw 'Installer returned a failure for the multi-repository fixture.' }
    foreach ($repository in @($firstRepository, $secondRepository)) {
        $content = [System.IO.File]::ReadAllText((Join-Path -Path $repository -ChildPath 'AGENTS.md'))
        Assert-True -Condition $content.Contains('<!-- ph4ge:begin v1 -->') -Message "managed block exists in $(Split-Path -Leaf $repository)"
    }

    $whatIfWorkspace = Join-Path -Path $temporaryRoot -ChildPath 'whatif-workspace'
    New-Item -ItemType Directory -Path $whatIfWorkspace | Out-Null
    Initialize-TestRepository -Path (Join-Path -Path $whatIfWorkspace -ChildPath 'dry-run-repository')
    & $installer -WorkspaceRoot $whatIfWorkspace -WhatIf
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path -Path $whatIfWorkspace -ChildPath 'AGENTS.md'))) -Message 'WhatIf does not create root AGENTS.md'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path -Path $whatIfWorkspace -ChildPath 'dry-run-repository/AGENTS.md'))) -Message 'WhatIf does not create child AGENTS.md'

    Write-Host 'PASS: PH4GE PowerShell installer fixtures completed successfully.'
} finally {
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
    if (Test-Path -LiteralPath $temporaryRoot) {
        $resolvedTemporary = [System.IO.Path]::GetFullPath($temporaryRoot)
        $expectedPrefix = Join-Path -Path $tempBase -ChildPath 'ph4ge-test-'
        if ($resolvedTemporary.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        } else {
            Write-Warning "Test cleanup refused an unexpected path: $temporaryRoot"
        }
    }
}
