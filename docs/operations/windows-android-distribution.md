# Atlas Distribution Targets (Windows + Android)

## Requested user targets
- Windows app for `Yosef` and `Benny`
- Android app for `Yosef` and `Yasha`

## Windows packaging
Project:
- `/Users/avrohom/Downloads/journeyatlas/windows-app/AtlasMasaWindows/AtlasMasaWindows.csproj`

Publish commands (from Windows PowerShell):
- `.\windows-app\scripts\publish-windows.ps1 -Arch x64 -Configuration Release`
- `.\windows-app\scripts\publish-windows.ps1 -Arch arm64 -Configuration Release`

Performance profile behavior:
- Auto-detects cores + memory.
- Enables higher queue worker concurrency on stronger hardware.
- Uses ReadyToRun + tiered JIT + server GC.

## Android packaging
Project:
- `/Users/avrohom/Downloads/journeyatlas/android-app`

Flavors:
- `yosef`
- `yasha`

Build:
- `./gradlew :app:assembleYosefRelease`
- `./gradlew :app:assembleYashaRelease`

Notes:
- Flavor split allows independent APK/AAB distribution while keeping feature parity.
- Runtime queue processing increases throughput on stronger devices and stays balanced on weaker devices.
