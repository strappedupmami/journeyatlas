param(
    [ValidateSet("x64", "arm64")]
    [string]$Arch = "x64",
    [string]$Configuration = "Release",
    [string]$Version = "1.0.0",
    [switch]$BuildRust = $true,
    [switch]$ReturnPublishDir
)

$ErrorActionPreference = "Stop"

$scriptRoot = Resolve-Path $PSScriptRoot
$root = Resolve-Path (Join-Path $scriptRoot "..")
$project = Join-Path $root "AtlasMasaWindows\AtlasMasaWindows.csproj"
$rid = if ($Arch -eq "arm64") { "win10-arm64" } else { "win10-x64" }
$outDir = Join-Path $root ("publish\{0}\{1}" -f $Version, $rid)

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

$numericVersion = Normalize-NumericVersion -RawVersion $Version

$rustReasonerBinary = $null
if ($BuildRust) {
    $rustProject = Join-Path $root "rust-atlas-reasoner"
    if (Test-Path $rustProject) {
        $cargo = Get-Command cargo -ErrorAction SilentlyContinue
        if ($null -eq $cargo) {
            Write-Warning "cargo is not available on PATH. Continuing without rebuilding Rust reasoner."
        } else {
            $rustTarget = if ($Arch -eq "arm64") { "aarch64-pc-windows-msvc" } else { "x86_64-pc-windows-msvc" }
            Push-Location $rustProject
            try {
                Write-Host "Building Rust reasoner ($rustTarget)..."
                & cargo build --release --target $rustTarget
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Rust reasoner build failed for $rustTarget. Continuing without rebuilding Rust reasoner."
                } else {
                    $targetBinary = Join-Path $rustProject ("target\{0}\release\atlas-rust-reasoner.exe" -f $rustTarget)
                    $fallbackBinary = Join-Path $rustProject "target\release\atlas-rust-reasoner.exe"
                    if (Test-Path $targetBinary) {
                        $rustReasonerBinary = $targetBinary
                    } elseif (Test-Path $fallbackBinary) {
                        $rustReasonerBinary = $fallbackBinary
                    } else {
                        Write-Warning "Rust reasoner build succeeded but binary was not found in expected target directories."
                    }
                }
            } finally {
                Pop-Location
            }
        }
    }
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Host "Publishing Atlas Windows for $rid ($Configuration)..."
$dotnetArgs = @(
    "publish",
    $project,
    "-c", $Configuration,
    "-r", $rid,
    "/p:PublishReadyToRun=true",
    "/p:TieredCompilation=true",
    "/p:ServerGarbageCollection=true",
    "/p:SelfContained=true",
    "/p:WindowsAppSDKSelfContained=true",
    "/p:PublishSingleFile=false",
    "/p:PublishTrimmed=false",
    "/p:DebugType=None",
    "/p:DebugSymbols=false",
    "/p:Version=$Version",
    "/p:AssemblyVersion=$numericVersion",
    "/p:FileVersion=$numericVersion",
    "/p:InformationalVersion=$Version",
    "-o", $outDir
)
if ($rustReasonerBinary) {
    $dotnetArgs += "/p:RustReasonerBinary=$rustReasonerBinary"
}
& dotnet @dotnetArgs
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed."
}

Write-Host "Done: $outDir"
if ($ReturnPublishDir) {
    Write-Output $outDir
}
