[CmdletBinding()]
param(
    [ValidateSet("all", "shared", "unified")]
    [string]$Target = "all",
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repositoryRoot "dist"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path (Get-Location) $OutputDirectory
}

$sourcePath = Join-Path $repositoryRoot "src"
if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
    throw "Could not find $sourcePath"
}

$outputDirectoryPath = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $outputDirectoryPath | Out-Null

if ($Target -notin @("all", "shared", "unified")) {
    throw "Target must be all, shared, or unified"
}

$manifestPath = Join-Path $repositoryRoot "info.toml"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Could not find $manifestPath"
}

$artifactPath = Join-Path $outputDirectoryPath "chugmania-webhooks.op"
$temporaryZip = Join-Path $outputDirectoryPath "$([guid]::NewGuid()).zip"
try {
    Push-Location $repositoryRoot
    try {
        Compress-Archive -LiteralPath "info.toml", "src" -DestinationPath $temporaryZip -CompressionLevel Optimal
    } finally {
        Pop-Location
    }
    Copy-Item -LiteralPath $temporaryZip -Destination $artifactPath -Force
    Write-Output "Created $artifactPath"
} finally {
    Remove-Item -LiteralPath $temporaryZip -Force -ErrorAction SilentlyContinue
}
