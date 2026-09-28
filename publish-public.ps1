[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9-]+$')]
    [string]$GitHubOwner,

    [string]$RepositoryPath,

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$RepositoryName,

    [string]$CommitMessage = 'Initial PH4GE release'
)

# ph4ge:managed-file v1
# Run this script yourself after reviewing the local repository. It creates a
# public GitHub repository only when origin is absent, then commits and pushes
# the current local changes to main. It never force-pushes or replaces origin.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryPath)) {
    $RepositoryPath = $PSScriptRoot
}

function Invoke-RequiredCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw $FailureMessage
    }
}

function Get-GitOutput {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $result = & git @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($result -join "`n").Trim()
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git is required but was not found on PATH.'
}
$ghCommand = Get-Command gh -ErrorAction SilentlyContinue
$ghCandidates = @(
    if ($ghCommand) { $ghCommand.Source }
    if ($env:ProgramFiles) { Join-Path -Path $env:ProgramFiles -ChildPath 'GitHub CLI\gh.exe' }
    if (${env:ProgramFiles(x86)}) { Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'GitHub CLI\gh.exe' }
    if ($env:LOCALAPPDATA) { Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs\GitHub CLI\gh.exe' }
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$ghExecutable = $ghCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $ghExecutable) {
    throw 'GitHub CLI is required but was not found on PATH.'
}
if (-not (Test-Path -LiteralPath $RepositoryPath -PathType Container)) {
    throw "Repository path is not a directory: $RepositoryPath"
}

$repository = (Resolve-Path -LiteralPath $RepositoryPath).Path
if (-not (Test-Path -LiteralPath (Join-Path -Path $repository -ChildPath '.git'))) {
    throw "Repository path is not a Git worktree: $repository"
}
if ([string]::IsNullOrWhiteSpace($RepositoryName)) {
    $RepositoryName = Split-Path -Leaf $repository
}

& $ghExecutable auth status 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'GitHub CLI is not authenticated. Run: gh auth login'
}

$branch = Get-GitOutput -Arguments @('-C', $repository, 'branch', '--show-current')
if ($branch -ne 'main') {
    throw "Expected branch 'main', found '$branch'. Switch to main before publishing."
}

& git -C $repository var GIT_AUTHOR_IDENT 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Git author identity is not configured. Set user.name and user.email before publishing.'
}

$repositorySlug = "$GitHubOwner/$RepositoryName"
$expectedSsh = "git@github.com:$repositorySlug.git"
$expectedHttps = "https://github.com/$repositorySlug.git"
$remoteNames = Get-GitOutput -Arguments @('-C', $repository, 'remote')
$origin = if (($remoteNames -split "`r?`n") -contains 'origin') {
    Get-GitOutput -Arguments @('-C', $repository, 'remote', 'get-url', 'origin')
} else {
    $null
}

if ($origin) {
    if ($origin -ne $expectedSsh -and $origin -ne $expectedHttps) {
        throw "Existing origin does not match ${repositorySlug}: $origin. The script will not replace it."
    }
    Write-Host "Origin already points to $repositorySlug."
} elseif ($PSCmdlet.ShouldProcess("GitHub repository $repositorySlug", 'create public repository and add origin')) {
    Invoke-RequiredCommand -FilePath $ghExecutable -Arguments @(
        'repo', 'create', $repositorySlug, '--public', '--source', $repository, '--remote', 'origin'
    ) -FailureMessage "Could not create public GitHub repository $repositorySlug."
}

$changes = Get-GitOutput -Arguments @('-C', $repository, 'status', '--porcelain')
if ($changes) {
    if ($PSCmdlet.ShouldProcess($repository, 'stage all current repository changes')) {
        Invoke-RequiredCommand -FilePath 'git' -Arguments @('-C', $repository, 'add', '--all') -FailureMessage 'Could not stage repository changes.'
    }

    & git -C $repository diff --cached --quiet
    $hasStagedChanges = $LASTEXITCODE -ne 0
    if ($hasStagedChanges -and $PSCmdlet.ShouldProcess($repository, "create commit '$CommitMessage'")) {
        Invoke-RequiredCommand -FilePath 'git' -Arguments @('-C', $repository, 'commit', '-m', $CommitMessage) -FailureMessage 'Could not create the initial commit.'
    }
} else {
    Write-Host 'No working-tree changes to commit.'
}

if ($PSCmdlet.ShouldProcess("origin/main for $repositorySlug", 'push branch without force')) {
    Invoke-RequiredCommand -FilePath 'git' -Arguments @('-C', $repository, 'push', '-u', 'origin', 'main') -FailureMessage 'Could not push main to origin.'
}

Write-Host "Published $repositorySlug."
