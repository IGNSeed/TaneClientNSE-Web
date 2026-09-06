[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$SourceReleaseDirectory,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [string]$OutputDirectory = '',

    [ValidatePattern('^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$')]
    [string]$Repository = 'IGNSeed/TaneClientNSE-Web'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot '..\.release'
}

$sourceRoot = (Resolve-Path -LiteralPath $SourceReleaseDirectory).Path
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$releaseRoot = [System.IO.Path]::GetFullPath((Join-Path $outputRoot "v$Version"))
$expectedPrefix = $outputRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) +
    [System.IO.Path]::DirectorySeparatorChar

if (-not $releaseRoot.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Resolved release directory is outside the requested output directory.'
}

if (Test-Path -LiteralPath $releaseRoot) {
    throw "Release staging already exists: $releaseRoot"
}

$sourceSubsdk = Join-Path $sourceRoot 'subsdk4'
$sourceNpdm = Join-Path $sourceRoot 'main.npdm'
foreach ($requiredFile in @($sourceSubsdk, $sourceNpdm)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required Release artifact is missing: $requiredFile"
    }
}

$packageExefs = Join-Path $releaseRoot 'package\atmosphere\contents\01006BD001E06000\exefs'
New-Item -ItemType Directory -Path $packageExefs -Force | Out-Null

$stagedSubsdk = Join-Path $releaseRoot 'subsdk4'
$stagedNpdm = Join-Path $releaseRoot 'main.npdm'
Copy-Item -LiteralPath $sourceSubsdk -Destination $stagedSubsdk
Copy-Item -LiteralPath $sourceNpdm -Destination $stagedNpdm
Copy-Item -LiteralPath $sourceSubsdk -Destination (Join-Path $packageExefs 'subsdk4')
Copy-Item -LiteralPath $sourceNpdm -Destination (Join-Path $packageExefs 'main.npdm')

$zipPath = Join-Path $releaseRoot "TaneClientNSE-v$Version.zip"
$packageAtmosphere = Join-Path $releaseRoot 'package\atmosphere'
Compress-Archive -LiteralPath $packageAtmosphere -DestinationPath $zipPath -CompressionLevel Optimal

function Get-IntegrityRecord {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path
    [ordered]@{
        size = $item.Length
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$subsdkIntegrity = Get-IntegrityRecord -Path $stagedSubsdk
$npdmIntegrity = Get-IntegrityRecord -Path $stagedNpdm
$zipIntegrity = Get-IntegrityRecord -Path $zipPath
$downloadRoot = "https://github.com/$Repository/releases/download/v$Version"

$manifest = [ordered]@{
    schema = 1
    version = $Version
    channel = 'stable'
    assets = [ordered]@{
        subsdk4 = [ordered]@{
            url = "$downloadRoot/subsdk4"
            sha256 = $subsdkIntegrity.sha256
            size = $subsdkIntegrity.size
        }
        main_npdm = [ordered]@{
            url = "$downloadRoot/main.npdm"
            sha256 = $npdmIntegrity.sha256
            size = $npdmIntegrity.size
        }
    }
}

$integrity = [ordered]@{
    version = $Version
    artifacts = [ordered]@{
        subsdk4 = $subsdkIntegrity
        main_npdm = $npdmIntegrity
        "TaneClientNSE-v$Version.zip" = $zipIntegrity
    }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText(
    (Join-Path $releaseRoot 'update.json'),
    (($manifest | ConvertTo-Json -Depth 5) + [Environment]::NewLine),
    $utf8NoBom)
[System.IO.File]::WriteAllText(
    (Join-Path $releaseRoot 'integrity.json'),
    (($integrity | ConvertTo-Json -Depth 5) + [Environment]::NewLine),
    $utf8NoBom)

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $expectedEntries = @(
        'atmosphere/contents/01006BD001E06000/exefs/main.npdm',
        'atmosphere/contents/01006BD001E06000/exefs/subsdk4'
    )
    $actualEntries = @($archive.Entries |
        ForEach-Object { $_.FullName.Replace('\', '/') } |
        Where-Object { -not $_.EndsWith('/') } |
        Sort-Object)
    $entryDifference = @(Compare-Object -ReferenceObject $expectedEntries -DifferenceObject $actualEntries)
    if ($entryDifference.Count -ne 0) {
        throw "ZIP structure verification failed: $($actualEntries -join ', ')"
    }
}
finally {
    $archive.Dispose()
}

if ((Get-FileHash -LiteralPath $sourceSubsdk -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath (Join-Path $packageExefs 'subsdk4') -Algorithm SHA256).Hash) {
    throw 'ZIP staging subsdk4 does not match the source artifact.'
}
if ((Get-FileHash -LiteralPath $sourceNpdm -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath (Join-Path $packageExefs 'main.npdm') -Algorithm SHA256).Hash) {
    throw 'ZIP staging main.npdm does not match the source artifact.'
}

Write-Host "Release preparation PASS: $releaseRoot"
Write-Host ($integrity | ConvertTo-Json -Depth 5)
Write-Host 'No files were uploaded.'
