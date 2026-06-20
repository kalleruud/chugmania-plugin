[CmdletBinding()]
param(
    [ValidateSet("trackmania", "turbo", "all")]
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

function Get-MetaValue([string]$Metadata, [string]$Key) {
    $metaMatch = [regex]::Match($Metadata, '(?ms)^\[meta\]\s*$\s*(.*?)(?=^\[|\z)')
    if (-not $metaMatch.Success) {
        throw "Could not find [meta] in manifest"
    }
    $match = [regex]::Match(
        $metaMatch.Groups[1].Value,
        "(?m)^\s*$([regex]::Escape($Key))\s*=\s*`"([^`"]+)`"\s*$"
    )
    if (-not $match.Success) {
        throw "Could not read [meta].$Key from manifest"
    }
    return $match.Groups[1].Value
}

$targets = if ($Target -eq "all") { @("trackmania", "turbo") } else { @($Target) }
$outputDirectoryPath = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $outputDirectoryPath | Out-Null

foreach ($game in $targets) {
    $manifestPath = if ($game -eq "trackmania") {
        Join-Path $repositoryRoot "info.toml"
    } else {
        Join-Path $repositoryRoot "manifests\info.turbo.toml"
    }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Could not find $manifestPath"
    }

    $metadata = Get-Content -LiteralPath $manifestPath -Raw
    $name = Get-MetaValue $metadata "name"
    $version = Get-MetaValue $metadata "version"
    $slug = ($name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        throw "Plugin name does not produce a valid artifact slug"
    }

    $artifactPath = Join-Path $outputDirectoryPath "$slug-$game-v$version.op"
    $stagingPath = Join-Path $outputDirectoryPath ".build-$game-$([guid]::NewGuid())"
    $temporaryZip = Join-Path $outputDirectoryPath "$([guid]::NewGuid()).zip"
    try {
        New-Item -ItemType Directory -Path $stagingPath | Out-Null
        Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $stagingPath "info.toml")
        Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $stagingPath "src") -Recurse
        Push-Location $stagingPath
        try {
            Compress-Archive -LiteralPath "info.toml", "src" -DestinationPath $temporaryZip -CompressionLevel Optimal
        } finally {
            Pop-Location
        }
        Copy-Item -LiteralPath $temporaryZip -Destination $artifactPath -Force
        Write-Output "Created $artifactPath"
    } finally {
        Remove-Item -LiteralPath $temporaryZip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
