; Inno Setup script for Snapline Windows
; Build with: ISCC.exe Snapline.iss
; Produces:   ..\dist\Snapline-Setup-{version}.exe

#define MyAppName        "Snapline"
; MyAppVersion is normally injected by build.ps1 via /DMyAppVersion=<x.y.z>
; (which reads /VERSION at the repo root). The fallback below only kicks in
; when ISCC is invoked directly without that flag.
#ifndef MyAppVersion
  #define MyAppVersion   "0.3.0"
#endif
#define MyAppPublisher   "studionope"
#define MyAppURL         "https://github.com/N-O-P-E/snapline"
#define MyAppExeName     "Snapline.exe"
#define MyAppId          "{{C7B4F5A0-9D3E-4F8B-A3C1-2D8F6E5A4B0E}"
#define BuildDir         "..\build"
#define DistDir          "..\dist"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
OutputDir={#DistDir}
OutputBaseFilename=Snapline-Setup-{#MyAppVersion}
SetupIconFile=..\Snapline\Resources\Snapline.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
MinVersion=10.0.17763
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "autostart";   Description: "Launch Snapline when I log in";       GroupDescription: "Startup:"; Flags: checkedonce

[Files]
Source: "{#BuildDir}\Snapline.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}";              Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}";    Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}";        Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; \
  ValueType: string; ValueName: "Snapline"; \
  ValueData: """{app}\{#MyAppExeName}"""; \
  Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
