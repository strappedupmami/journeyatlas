param(
    [ValidateSet("x64", "arm64")]
    [string]$Arch = "x64",
    [string]$Configuration = "Release",
    [string]$Version = "1.0.0",
    [string]$Publisher = "BlackHaven",
    [string]$Website = "https://atlasmasa.com",
    [switch]$SkipRustBuild,
    [switch]$SkipInstaller,
    [string]$InnoSetupCompilerPath = "",
    [string]$SignThumbprint = "",
    [string]$SignToolPath = "",
    [string]$TimestampUrl = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"

function Resolve-IsccPath {
    param([string]$PreferredPath)

    if (![string]::IsNullOrWhiteSpace($PreferredPath)) {
        if (Test-Path $PreferredPath) {
            return (Resolve-Path $PreferredPath).Path
        }
        throw "Provided Inno Setup compiler path does not exist: $PreferredPath"
    }

    $defaultPaths = @(
        "$env:ProgramFiles(x86)\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    )
    foreach ($candidate in $defaultPaths) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    $command = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    throw "Inno Setup compiler (ISCC.exe) not found. Install Inno Setup 6 or provide -InnoSetupCompilerPath."
}

function Resolve-SignToolPath {
    param([string]$PreferredPath)

    if (![string]::IsNullOrWhiteSpace($PreferredPath)) {
        if (Test-Path $PreferredPath) {
            return (Resolve-Path $PreferredPath).Path
        }
        throw "Provided signtool path does not exist: $PreferredPath"
    }

    $command = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $candidateRoots = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin",
        "$env:ProgramFiles\Windows Kits\10\bin"
    )
    foreach ($rootPath in $candidateRoots) {
        if (!(Test-Path $rootPath)) {
            continue
        }
        $found = Get-ChildItem -Path $rootPath -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($found) {
            return $found.FullName
        }
    }

    throw "signtool.exe not found. Install Windows SDK or provide -SignToolPath."
}

$scriptRoot = Resolve-Path $PSScriptRoot
$root = Resolve-Path (Join-Path $scriptRoot "..")
$publishScript = Join-Path $scriptRoot "publish-windows.ps1"
$installerScript = Join-Path $root "installer\AtlasMasaWindows.iss"
if (!(Test-Path $installerScript)) {
    throw "Installer script not found: $installerScript"
}

Write-Host "Publishing app payload..."
$publishDir = & $publishScript `
    -Arch $Arch `
    -Configuration $Configuration `
    -Version $Version `
    -BuildRust:(!$SkipRustBuild) `
    -ReturnPublishDir

if ($LASTEXITCODE -ne 0) {
    throw "Publish step failed."
}

$publishDir = (Resolve-Path $publishDir).Path
$appExe = Join-Path $publishDir "AtlasMasaWindows.exe"
if (!(Test-Path $appExe)) {
    throw "Published executable not found: $appExe"
}

$releaseDir = Join-Path $root ("release\{0}\{1}" -f $Version, $Arch)
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

if (-not $SkipInstaller) {
    $iscc = Resolve-IsccPath -PreferredPath $InnoSetupCompilerPath
    Write-Host "Building installer with Inno Setup..."
    & $iscc `
        "/DAppVersion=$Version" `
        "/DAppPublisher=$Publisher" `
        "/DAppURL=$Website" `
        "/DArch=$Arch" `
        "/DPublishDir=$publishDir" `
        "/DOutputDir=$releaseDir" `
        $installerScript

    if ($LASTEXITCODE -ne 0) {
        throw "Installer build failed."
    }
}

Write-Host "Creating portable ZIP..."
$zipPath = Join-Path $releaseDir ("AtlasMasa-Windows-{0}-{1}-portable.zip" -f $Version, $Arch)
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}
Compress-Archive -Path (Join-Path $publishDir "*") -DestinationPath $zipPath -Force

$installerPath = $null
if (-not $SkipInstaller) {
    $installerPath = Get-ChildItem -Path $releaseDir -Filter ("AtlasMasa-Setup-{0}-{1}*.exe" -f $Version, $Arch) |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $installerPath) {
        throw "Installer output not found in $releaseDir"
    }

    if (![string]::IsNullOrWhiteSpace($SignThumbprint)) {
        $signtool = Resolve-SignToolPath -PreferredPath $SignToolPath
        Write-Host "Signing installer with certificate thumbprint $SignThumbprint..."
        & $signtool sign /sha1 $SignThumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 $installerPath.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "signtool failed for installer."
        }
    }
}

$checksums = New-Object System.Collections.Generic.List[string]
if ($installerPath) {
    $installerHash = Get-FileHash -Path $installerPath.FullName -Algorithm SHA256
    $checksums.Add(("{0} *{1}" -f $installerHash.Hash.ToLowerInvariant(), $installerPath.Name))
}
$zipHash = Get-FileHash -Path $zipPath -Algorithm SHA256
$checksums.Add(("{0} *{1}" -f $zipHash.Hash.ToLowerInvariant(), (Split-Path $zipPath -Leaf)))

$checksumsPath = Join-Path $releaseDir "SHA256SUMS.txt"
Set-Content -Path $checksumsPath -Value ($checksums -join [Environment]::NewLine) -Encoding UTF8

$manifest = [ordered]@{
    version = $Version
    arch = $Arch
    configuration = $Configuration
    generated_at_utc = [DateTime]::UtcNow.ToString("o")
    publisher = $Publisher
    website = $Website
    installer = if ($installerPath) {
        [ordered]@{
            file = $installerPath.Name
            sha256 = (Get-FileHash -Path $installerPath.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    } else {
        $null
    }
    portable_zip = [ordered]@{
        file = (Split-Path $zipPath -Leaf)
        sha256 = $zipHash.Hash.ToLowerInvariant()
    }
}
$manifestPath = Join-Path $releaseDir "release-manifest.json"
$manifest | ConvertTo-Json -Depth 8 | Set-Content -Path $manifestPath -Encoding UTF8

Write-Host "Release artifacts ready:"
if ($installerPath) {
    Write-Host ("  Installer: {0}" -f $installerPath.FullName)
}
Write-Host ("  Portable ZIP: {0}" -f $zipPath)
Write-Host ("  Checksums: {0}" -f $checksumsPath)
Write-Host ("  Manifest: {0}" -f $manifestPath)
