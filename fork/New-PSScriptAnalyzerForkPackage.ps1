#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds the release zip of this fork and its SHA-256 file.

.DESCRIPTION
    The script builds the module for Windows PowerShell 5.1 and for PowerShell 7 with
    ./build.ps1 -Configuration Release -All, after ./build.ps1 -Clean. The zip holds the folder
    out/PSScriptAnalyzer/<ModuleVersion> at its root, the layout of the gallery package without its
    NuGet files and its signatures.

    Each entry of the zip has the time of the commit, and the entries are in ordinal order. Two
    builds of one commit with the same .NET SDK therefore give the same bytes and the same SHA-256.

    Run it on a clean checkout of the tag, for example v1.25.0-quindos.1. The build needs the .NET
    SDK of global.json and platyPS 0.14.2 (tools/installPSResources.ps1).

.PARAMETER Release
    The fork release, such as quindos.1. It must match Prerelease in Engine/PSScriptAnalyzer.psd1
    without its dot. The file is PSScriptAnalyzer-<ModuleVersion>-<Release>.zip.

.PARAMETER OutDir
    The folder for the zip and the .sha256 file. Defaults to dist beside the repository root.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidatePattern('^quindos\.\d+$')] [string]$Release,
    [string]$OutDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $root 'dist' }
if (git -C $root status --porcelain) { throw "The checkout at $root has changes. Build the package from a clean checkout of the tag." }

$source = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'Engine/PSScriptAnalyzer.psd1')
$prerelease = $source.PrivateData.PSData.Prerelease
if ($prerelease -ne ($Release -replace '\.', '')) {
    throw "Engine/PSScriptAnalyzer.psd1 gives the Prerelease '$prerelease', and the release is $Release."
}

& (Join-Path $root 'build.ps1') -Clean
& (Join-Path $root 'build.ps1') -Configuration Release -All
$moduleRoot = Get-ChildItem -LiteralPath (Join-Path $root 'out/PSScriptAnalyzer') -Directory | Select-Object -First 1
$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $moduleRoot.FullName 'PSScriptAnalyzer.psd1')
if ($manifest.ModuleVersion -ne $moduleRoot.Name) {
    throw "The build gives the folder $($moduleRoot.Name) and the ModuleVersion $($manifest.ModuleVersion)."
}

$name = "PSScriptAnalyzer-$($manifest.ModuleVersion)-$Release"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$zip = Join-Path $OutDir "$name.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip }

$commitTime = [DateTimeOffset]::Parse((git -C $root log -1 --format=%cI HEAD))
$prefix = $moduleRoot.FullName.Length + 1
$files = Get-ChildItem -LiteralPath $moduleRoot.FullName -Recurse -File |
    ForEach-Object { [pscustomobject]@{ Path = $_.FullName; Entry = $_.FullName.Substring($prefix) -replace '\\', '/' } } |
    Sort-Object -Property Entry -Culture ([Globalization.CultureInfo]::InvariantCulture) -CaseSensitive

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $files) {
        $entry = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.Path, $file.Entry, [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $commitTime
    }
}
finally { $archive.Dispose() }

$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath "$zip.sha256" -Value "$hash  $name.zip" -Encoding ascii -NoNewline
Write-Host "$zip"
Write-Host "SHA-256 $hash"
