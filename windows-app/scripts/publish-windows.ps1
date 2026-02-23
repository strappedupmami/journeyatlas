param(
    [ValidateSet("x64", "arm64")]
    [string]$Arch = "x64",
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

$project = Join-Path $PSScriptRoot "..\AtlasMasaWindows\AtlasMasaWindows.csproj"
$rid = if ($Arch -eq "arm64") { "win10-arm64" } else { "win10-x64" }
$outDir = Join-Path $PSScriptRoot "..\publish\$rid"

Write-Host "Publishing Atlas Windows for $rid ($Configuration)..."
dotnet publish $project `
  -c $Configuration `
  -r $rid `
  /p:PublishReadyToRun=true `
  /p:TieredCompilation=true `
  /p:ServerGarbageCollection=true `
  /p:PublishSingleFile=false `
  -o $outDir

Write-Host "Done: $outDir"
