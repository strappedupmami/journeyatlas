param(
    [ValidateSet("x64", "arm64")]
    [string]$Arch = "x64",
    [string]$Configuration = "Release",
    [string]$Version = "1.0.0",
    [string]$ArtifactPrefix = "AtlasMasa",
    [string]$AppInstallerBaseUrl = "",
    [string]$AppDisplayName = "Atlas Masa",
    [switch]$BuildRust = $true,
    [switch]$AllowUnsigned = $false,
    [string]$SigningThumbprint = "",
    [switch]$CreateWebLanding = $true,
    [switch]$CreateShopifyZip = $true
)

$ErrorActionPreference = "Stop"

function Normalize-NumericVersion {
    param([string]$RawVersion)

    $head = ($RawVersion -split "-", 2)[0]
    $parts = $head -split "\."
    $numeric = @()
    foreach ($part in $parts) {
        if ($part -match "^\d+$") {
            $numeric += $part
        } else {
            break
        }
    }

    while ($numeric.Count -lt 4) {
        $numeric += "0"
    }
    if ($numeric.Count -gt 4) {
        $numeric = $numeric[0..3]
    }

    return ($numeric -join ".")
}

function Resolve-RustBinary {
    param(
        [string]$RepoRoot,
        [string]$TargetArch
    )

    $rustProject = Join-Path $RepoRoot "rust-atlas-reasoner"
    if (!(Test-Path $rustProject)) {
        return $null
    }

    $cargo = Get-Command cargo -ErrorAction SilentlyContinue
    if ($null -eq $cargo) {
        Write-Warning "cargo is not available on PATH. Continuing without rebuilding Rust reasoner."
        return $null
    }

    $targetTriple = if ($TargetArch -eq "arm64") { "aarch64-pc-windows-msvc" } else { "x86_64-pc-windows-msvc" }
    Push-Location $rustProject
    try {
        Write-Host "Building Rust reasoner ($targetTriple)..."
        & cargo build --release --target $targetTriple
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Rust reasoner build failed for $targetTriple. Continuing without Rust sidecar in package."
            return $null
        }
    } finally {
        Pop-Location
    }

    $candidate = Join-Path $rustProject ("target\{0}\release\atlas-rust-reasoner.exe" -f $targetTriple)
    if (Test-Path $candidate) {
        return (Resolve-Path $candidate).Path
    }

    return $null
}

function Ensure-AbsoluteHttpsBaseUrl {
    param([string]$Raw)

    if ([string]::IsNullOrWhiteSpace($Raw)) {
        throw "AppInstallerBaseUrl is required. Example: https://downloads.atlasmasa.com/windows/stable/x64/"
    }

    $trimmed = $Raw.Trim()
    if (-not $trimmed.EndsWith("/")) {
        $trimmed += "/"
    }

    $uri = $null
    if (-not [Uri]::TryCreate($trimmed, [UriKind]::Absolute, [ref]$uri)) {
        throw "Invalid AppInstallerBaseUrl: $Raw"
    }
    if ($uri.Scheme -ne "https") {
        throw "AppInstallerBaseUrl must use https."
    }

    return $uri.AbsoluteUri
}

function Get-MsixIdentity {
    param([string]$MsixPath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($MsixPath)
    try {
        $manifestEntry = $archive.Entries |
            Where-Object { $_.FullName -eq "AppxManifest.xml" } |
            Select-Object -First 1
        if ($null -eq $manifestEntry) {
            throw "AppxManifest.xml was not found inside $MsixPath"
        }

        $stream = $manifestEntry.Open()
        $reader = New-Object System.IO.StreamReader($stream)
        try {
            $xmlText = $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
            $stream.Dispose()
        }
    } finally {
        $archive.Dispose()
    }

    [xml]$xmlDoc = $xmlText
    $ns = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
    $ns.AddNamespace("appx", "http://schemas.microsoft.com/appx/manifest/foundation/windows10")

    $identity = $xmlDoc.SelectSingleNode("/appx:Package/appx:Identity", $ns)
    if ($null -eq $identity) {
        throw "Identity node was not found in AppxManifest.xml."
    }

    return [ordered]@{
        name = $identity.Attributes["Name"].Value
        publisher = $identity.Attributes["Publisher"].Value
        version = $identity.Attributes["Version"].Value
        processor_architecture = $identity.Attributes["ProcessorArchitecture"].Value
    }
}

function Write-WebLandingPage {
    param(
        [string]$OutputPath,
        [string]$DisplayName,
        [string]$InstallLink,
        [string]$AppInstallerFileName,
        [string]$MsixFileName
    )

    $html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$DisplayName Install</title>
  <style>
    :root {
      color-scheme: dark;
      --bg-a: #0f1024;
      --bg-b: #1d0f1b;
      --card: rgba(255, 255, 255, 0.08);
      --line: rgba(255, 255, 255, 0.16);
      --text: #f5f7ff;
      --muted: #b9c0de;
      --accent-a: #dd3544;
      --accent-b: #f8884e;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      font-family: "Segoe UI", system-ui, sans-serif;
      background: radial-gradient(1100px 700px at 8% 8%, var(--bg-b), var(--bg-a));
      color: var(--text);
      padding: 24px;
    }
    .card {
      width: min(720px, 100%);
      border: 1px solid var(--line);
      border-radius: 18px;
      background: var(--card);
      backdrop-filter: blur(8px);
      padding: 28px;
    }
    h1 { margin: 0 0 10px 0; font-size: clamp(1.5rem, 3vw, 2rem); }
    p { margin: 0 0 14px 0; color: var(--muted); line-height: 1.5; }
    .row { display: flex; gap: 12px; flex-wrap: wrap; margin: 18px 0 8px 0; }
    .button {
      display: inline-block;
      border-radius: 10px;
      padding: 11px 16px;
      text-decoration: none;
      color: white;
      border: 1px solid transparent;
      font-weight: 600;
    }
    .button.primary {
      background: linear-gradient(90deg, var(--accent-a), var(--accent-b));
    }
    .button.secondary {
      border-color: var(--line);
      background: rgba(255, 255, 255, 0.05);
    }
    ol {
      margin: 10px 0 0 18px;
      color: var(--muted);
      padding: 0;
      line-height: 1.5;
    }
    code {
      background: rgba(255, 255, 255, 0.09);
      border-radius: 6px;
      padding: 2px 6px;
      color: #fff;
    }
  </style>
</head>
<body>
  <main class="card">
    <h1>Install $DisplayName</h1>
    <p>This is the recommended one-click Windows install path. It supports in-place updates like a managed app channel.</p>
    <div class="row">
      <a class="button primary" href="$InstallLink">Install Now</a>
      <a class="button secondary" href="./$AppInstallerFileName">Download .appinstaller</a>
      <a class="button secondary" href="./$MsixFileName">Download .msix</a>
    </div>
    <ol>
      <li>Click <code>Install Now</code> on a Windows PC.</li>
      <li>Approve the prompt from Windows App Installer.</li>
      <li>Launch $DisplayName from Start Menu.</li>
    </ol>
  </main>
</body>
</html>
"@

    Set-Content -Path $OutputPath -Value $html -Encoding UTF8
}

if (-not $AllowUnsigned -and [string]::IsNullOrWhiteSpace($SigningThumbprint)) {
    throw "Production App Installer builds require signing. Pass -SigningThumbprint or explicitly set -AllowUnsigned."
}

$numericVersion = Normalize-NumericVersion -RawVersion $Version
$baseUrl = Ensure-AbsoluteHttpsBaseUrl -Raw $AppInstallerBaseUrl
$scriptRoot = Resolve-Path $PSScriptRoot
$root = Resolve-Path (Join-Path $scriptRoot "..")
$project = Join-Path $root "AtlasMasaWindows\AtlasMasaWindows.csproj"
$rid = if ($Arch -eq "arm64") { "win10-arm64" } else { "win10-x64" }

$releaseDir = Join-Path $root ("release\{0}\{1}\appinstaller" -f $Version, $Arch)
$publishDir = Join-Path $releaseDir "publish"
$packageDir = Join-Path $releaseDir "msix"
$webDir = Join-Path $releaseDir "web"
$archiveDir = Join-Path $releaseDir "archive"

New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
New-Item -ItemType Directory -Force -Path $publishDir | Out-Null
New-Item -ItemType Directory -Force -Path $packageDir | Out-Null
New-Item -ItemType Directory -Force -Path $webDir | Out-Null
New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null

$rustBinary = $null
if ($BuildRust) {
    $rustBinary = Resolve-RustBinary -RepoRoot $root -TargetArch $Arch
}

$dotnetArgs = @(
    "publish",
    $project,
    "-c", $Configuration,
    "-r", $rid,
    "/p:SelfContained=true",
    "/p:WindowsAppSDKSelfContained=true",
    "/p:GenerateAppxPackageOnBuild=true",
    "/p:AppxPackageDir=$packageDir\",
    "/p:UapAppxPackageBuildMode=SideloadOnly",
    "/p:AppxBundle=Never",
    "/p:Version=$Version",
    "/p:AssemblyVersion=$numericVersion",
    "/p:FileVersion=$numericVersion",
    "/p:InformationalVersion=$Version",
    "/p:AppxPackageSigningEnabled=$([string](![string]::IsNullOrWhiteSpace($SigningThumbprint)).ToLowerInvariant())",
    "/p:PackageCertificateThumbprint=$SigningThumbprint",
    "-o", $publishDir
)
if ($rustBinary) {
    $dotnetArgs += "/p:RustReasonerBinary=$rustBinary"
}

Write-Host "Building MSIX package..."
& dotnet @dotnetArgs
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed for MSIX packaging."
}

$msix = Get-ChildItem -Path $packageDir -Filter *.msix -Recurse |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $msix) {
    throw "No .msix file found under $packageDir"
}

$identity = Get-MsixIdentity -MsixPath $msix.FullName

$stableMsixFile = "{0}-{1}.msix" -f $ArtifactPrefix, $Arch
$stableAppInstallerFile = "{0}-{1}.appinstaller" -f $ArtifactPrefix, $Arch
$versionedMsixFile = "{0}-{1}-{2}.msix" -f $ArtifactPrefix, $Version, $Arch
$versionedAppInstallerFile = "{0}-{1}-{2}.appinstaller" -f $ArtifactPrefix, $Version, $Arch

$stableMsixPath = Join-Path $webDir $stableMsixFile
$stableAppInstallerPath = Join-Path $webDir $stableAppInstallerFile
$versionedMsixPath = Join-Path $archiveDir $versionedMsixFile
$versionedAppInstallerPath = Join-Path $archiveDir $versionedAppInstallerFile

Copy-Item -Path $msix.FullName -Destination $stableMsixPath -Force
Copy-Item -Path $msix.FullName -Destination $versionedMsixPath -Force

$msixUrl = "{0}{1}" -f $baseUrl, $stableMsixFile
$appInstallerUrl = "{0}{1}" -f $baseUrl, $stableAppInstallerFile

$appInstallerXml = @"
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller
    xmlns="http://schemas.microsoft.com/appx/appinstaller/2018"
    Version="$($identity.version)"
    Uri="$appInstallerUrl">
  <MainPackage
      Name="$($identity.name)"
      Publisher="$($identity.publisher)"
      Version="$($identity.version)"
      ProcessorArchitecture="$($identity.processor_architecture)"
      Uri="$msixUrl" />
  <UpdateSettings>
    <OnLaunch HoursBetweenUpdateChecks="0" ShowPrompt="true" UpdateBlocksActivation="true" />
    <ForceUpdateFromAnyVersion>true</ForceUpdateFromAnyVersion>
  </UpdateSettings>
</AppInstaller>
"@
Set-Content -Path $stableAppInstallerPath -Value $appInstallerXml -Encoding UTF8
Set-Content -Path $versionedAppInstallerPath -Value $appInstallerXml -Encoding UTF8

$installLink = "ms-appinstaller:?source=$([Uri]::EscapeDataString($appInstallerUrl))"
$linkPath = Join-Path $webDir "INSTALL_LINK.txt"
Set-Content -Path $linkPath -Value $installLink -Encoding UTF8

$installCmdPath = Join-Path $webDir "Install-$ArtifactPrefix.cmd"
$installCmd = @(
    "@echo off",
    "start """" ""$installLink"""
) -join [Environment]::NewLine
Set-Content -Path $installCmdPath -Value $installCmd -Encoding ASCII

if ($CreateWebLanding) {
    Write-WebLandingPage `
        -OutputPath (Join-Path $webDir "index.html") `
        -DisplayName $AppDisplayName `
        -InstallLink $installLink `
        -AppInstallerFileName $stableAppInstallerFile `
        -MsixFileName $stableMsixFile
}

$shopifyZip = $null
if ($CreateShopifyZip) {
    $shopifyZip = Join-Path $releaseDir ("{0}-Windows-Install-{1}-{2}.zip" -f $ArtifactPrefix, $Version, $Arch)
    if (Test-Path $shopifyZip) {
        Remove-Item -Path $shopifyZip -Force
    }
    Compress-Archive -Path (Join-Path $webDir "*") -DestinationPath $shopifyZip -Force
}

$checksums = @()
$stableMsixHash = Get-FileHash -Path $stableMsixPath -Algorithm SHA256
$checksums += ("{0} *web/{1}" -f $stableMsixHash.Hash.ToLowerInvariant(), $stableMsixFile)
$stableAppInstallerHash = Get-FileHash -Path $stableAppInstallerPath -Algorithm SHA256
$checksums += ("{0} *web/{1}" -f $stableAppInstallerHash.Hash.ToLowerInvariant(), $stableAppInstallerFile)
$versionedMsixHash = Get-FileHash -Path $versionedMsixPath -Algorithm SHA256
$checksums += ("{0} *archive/{1}" -f $versionedMsixHash.Hash.ToLowerInvariant(), $versionedMsixFile)
$versionedAppInstallerHash = Get-FileHash -Path $versionedAppInstallerPath -Algorithm SHA256
$checksums += ("{0} *archive/{1}" -f $versionedAppInstallerHash.Hash.ToLowerInvariant(), $versionedAppInstallerFile)
if ($shopifyZip) {
    $shopifyZipHash = Get-FileHash -Path $shopifyZip -Algorithm SHA256
    $checksums += ("{0} *{1}" -f $shopifyZipHash.Hash.ToLowerInvariant(), (Split-Path $shopifyZip -Leaf))
}
Set-Content -Path (Join-Path $releaseDir "SHA256SUMS.txt") -Value ($checksums -join [Environment]::NewLine) -Encoding UTF8

$manifest = [ordered]@{
    version = $Version
    numeric_version = $numericVersion
    architecture = $Arch
    runtime_identifier = $rid
    generated_at_utc = [DateTime]::UtcNow.ToString("o")
    package_identity_name = $identity.name
    package_publisher = $identity.publisher
    package_identity_version = $identity.version
    package_processor_architecture = $identity.processor_architecture
    signed = (-not [string]::IsNullOrWhiteSpace($SigningThumbprint))
    web_bundle = [ordered]@{
        path = $webDir
        stable_msix_file = $stableMsixFile
        stable_appinstaller_file = $stableAppInstallerFile
        install_link_file = "INSTALL_LINK.txt"
        install_cmd_file = (Split-Path $installCmdPath -Leaf)
        landing_file = if ($CreateWebLanding) { "index.html" } else { $null }
    }
    archived_bundle = [ordered]@{
        path = $archiveDir
        msix_file = $versionedMsixFile
        appinstaller_file = $versionedAppInstallerFile
    }
    shopify_zip = if ($shopifyZip) {
        [ordered]@{
            file = (Split-Path $shopifyZip -Leaf)
            sha256 = (Get-FileHash -Path $shopifyZip -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    } else {
        $null
    }
    hosted_urls = [ordered]@{
        msix = $msixUrl
        appinstaller = $appInstallerUrl
        landing = if ($CreateWebLanding) { "{0}index.html" -f $baseUrl } else { $null }
    }
    install_link = $installLink
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $releaseDir "appinstaller-manifest.json") -Encoding UTF8

Write-Host "App Installer release artifacts ready:"
Write-Host ("  Web bundle: {0}" -f $webDir)
Write-Host ("  Stable MSIX: {0}" -f $stableMsixPath)
Write-Host ("  Stable AppInstaller: {0}" -f $stableAppInstallerPath)
if ($CreateWebLanding) {
    Write-Host ("  Landing page: {0}" -f (Join-Path $webDir "index.html"))
}
if ($shopifyZip) {
    Write-Host ("  Shopify ZIP: {0}" -f $shopifyZip)
}
Write-Host ("  Install link: {0}" -f $installLink)
Write-Host ("  Release dir: {0}" -f $releaseDir)
