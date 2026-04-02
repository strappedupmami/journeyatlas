## BlackHaven macOS Agent Notes

- Primary app project: `/Users/avrohom/Downloads/BlackHaven/macos-app/AtlasMasaMacOS.xcodeproj`
- Main sources: `/Users/avrohom/Downloads/BlackHaven/macos-app/AtlasMasaMacOS/Sources`
- Tests: `/Users/avrohom/Downloads/BlackHaven/macos-app/AtlasMasaMacOS/Tests/AtlasMasaMacOSTests.swift`

### Useful commands

- macOS build:
  - `xcodebuild -project /Users/avrohom/Downloads/BlackHaven/macos-app/AtlasMasaMacOS.xcodeproj -scheme AtlasMasaMacOS -destination 'platform=macOS' build`
- iOS companion build:
  - `xcodebuild -project /Users/avrohom/Downloads/BlackHaven/ios-app/AtlasMasaIOS.xcodeproj -scheme AtlasMasaIOS -destination 'generic/platform=iOS' build`

### Current local blocker

- On this machine, `xcodebuild` currently fails before project compilation because Apple plug-ins are not loading correctly.
- If builds fail immediately with `xcodebuild failed to load a required plug-in`, run:
  - `xcodebuild -runFirstLaunch`

### High-value product surfaces

- `Sources/App/RootDashboardView.swift`
- `Sources/Core/SessionStore.swift`
- `Sources/Features/Command/CommandCenterCard.swift`
- `Sources/Features/Queue/PromptQueueCard.swift`
- `Sources/Features/Workspaces/WorkspacesCard.swift`

### Stabilization priorities

- First-launch local AI setup and recovery UX
- Session restore and prompt queue persistence
- AI chat, workspace, and R&D navigation coherence
- Local memory-vault integrity and note chronology
