param(
    [ValidateSet("x64", "arm64")]
    [string]$Arch = "x64",
    [string]$Configuration = "Release",
    [string]$Version = "1.0.0",
    [string]$ArtifactPrefix = "AtlasMasa",
    [Parameter(Mandatory = $true)]
    [string]$AppInstallerBaseUrl,
    [string]$AppDisplayName = "Atlas Masa",
    [switch]$BuildRust = $true,
    [switch]$AllowUnsigned = $false,
    [string]$SigningThumbprint = ""
)

$ErrorActionPreference = "Stop"

if (-not $AllowUnsigned -and [string]::IsNullOrWhiteSpace($SigningThumbprint)) {
    throw "Production builds require signing. Pass -SigningThumbprint or explicitly use -AllowUnsigned for local testing only."
}

$scriptRoot = Resolve-Path $PSScriptRoot
$appInstallerScript = Join-Path $scriptRoot "build-windows-appinstaller.ps1"
if (!(Test-Path $appInstallerScript)) {
    throw "Missing script: $appInstallerScript"
}

Write-Host "Building DMG-style Windows install bundle..."
& $appInstallerScript `
    -Arch $Arch `
    -Configuration $Configuration `
    -Version $Version `
    -ArtifactPrefix $ArtifactPrefix `
    -AppInstallerBaseUrl $AppInstallerBaseUrl `
    -AppDisplayName $AppDisplayName `
    -BuildRust:$BuildRust `
    -AllowUnsigned:$AllowUnsigned `
    -SigningThumbprint $SigningThumbprint `
    -CreateWebLanding `
    -CreateShopifyZip

if ($LASTEXITCODE -ne 0) {
    throw "build-windows-appinstaller.ps1 failed."
}

Write-Host "Done."
