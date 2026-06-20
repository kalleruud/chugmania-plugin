[CmdletBinding()]
param(
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repositoryRoot "dist"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path (Get-Location) $OutputDirectory
}

$metadataPath = Join-Path $repositoryRoot "info.toml"
$sourcePath = Join-Path $repositoryRoot "src"

if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
    throw "Could not find $metadataPath"
}
if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
    throw "Could not find $sourcePath"
}

$metadata = Get-Content -LiteralPath $metadataPath -Raw
$metaMatch = [regex]::Match($metadata, '(?ms)^\[meta\]\s*$\s*(.*?)(?=^\[|\z)')
if (-not $metaMatch.Success) {
    throw "Could not find [meta] in info.toml"
}

function Get-MetaValue([string]$Key) {
    $match = [regex]::Match(
        $metaMatch.Groups[1].Value,
        "(?m)^\s*$([regex]::Escape($Key))\s*=\s*`"([^`"]+)`"\s*$"
    )
    if (-not $match.Success) {
        throw "Could not read [meta].$Key from info.toml"
    }
    return $match.Groups[1].Value
}

$name = Get-MetaValue "name"
$version = Get-MetaValue "version"
$slug = $name.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
$slug = $slug.Trim('-')
if ([string]::IsNullOrWhiteSpace($slug)) {
    throw "Plugin name does not produce a valid artifact slug"
}

$outputDirectoryPath = [System.IO.Path]::GetFullPath($OutputDirectory)
$artifactName = "$slug-v$version.op"
$artifactPath = Join-Path $outputDirectoryPath $artifactName
$temporaryZip = Join-Path $outputDirectoryPath "$([guid]::NewGuid()).zip"

New-Item -ItemType Directory -Force -Path $outputDirectoryPath | Out-Null

try {
    Push-Location $repositoryRoot
    try {
        Compress-Archive -LiteralPath "info.toml", "src" -DestinationPath $temporaryZip -CompressionLevel Optimal
    } finally {
        Pop-Location
    }

    Copy-Item -LiteralPath $temporaryZip -Destination $artifactPath -Force
} finally {
    Remove-Item -LiteralPath $temporaryZip -Force -ErrorAction SilentlyContinue
}

Write-Output "Created $artifactPath"
