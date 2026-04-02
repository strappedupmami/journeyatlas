#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif
#ifndef AppPublisher
  #define AppPublisher "BlackHaven"
#endif
#ifndef AppURL
  #define AppURL "https://blackhaven.app"
#endif
#ifndef Arch
  #define Arch "x64"
#endif
#ifndef PublishDir
  #error "PublishDir define is required. Example: /DPublishDir=C:\\path\\to\\publish"
#endif
#ifndef OutputDir
  #define OutputDir "..\\release"
#endif

#define AppName "BlackHaven"
#define AppExeName "AtlasMasaWindows.exe"

[Setup]
AppId={{B8D1D2F9-9D38-4FAE-AD3A-BF8ACCB7A104}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
DefaultDirName={autopf}\BlackHaven
DefaultGroupName=BlackHaven
OutputDir={#OutputDir}
OutputBaseFilename=AtlasMasa-Setup-{#AppVersion}-{#Arch}
ArchitecturesAllowed={#Arch}
ArchitecturesInstallIn64BitMode={#Arch}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
DisableDirPage=no
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion; Excludes: "*.pdb,*.xml"

[Icons]
Name: "{autoprograms}\BlackHaven"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\BlackHaven"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch BlackHaven"; Flags: nowait postinstall skipifsilent
