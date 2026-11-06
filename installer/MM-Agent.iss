; MM Agent installer: Hermes Agent (brain) + OpenClaw (interface).
; Ships only MM Agent's own scripts. Hermes and OpenClaw are downloaded by first-run.ps1,
; and each user enters their own API keys. No personal data is packaged.
; Build:  ISCC.exe MM-Agent.iss   ->  ..\dist\MM-Agent-Setup.exe

#define AppName "MM Agent"
#define AppVersion "1.1.4"
; Rooster icon, built from mmagent-source.jpg by make-icon.ps1.
#define AppIcon "mmagent.ico"

[Setup]
AppId={{0C0890F7-59B5-4825-AFC4-CABF1964BA33}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppName}
; Per-user install: no administrator rights needed, and the logs folder stays writable.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\MM Agent
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=MM-Agent-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#AppName}
SetupIconFile={#AppIcon}
UninstallDisplayIcon={app}\{#AppIcon}
SetupLogging=yes
; Inno 6.7+ turns on Windows' RedirectionGuard by default, and (tested) programs started from
; [Run] inherit it. It stops uv from following its own Python junctions, which breaks Hermes'
; install and start ("os error 448", "uv trampoline failed to spawn Python"). This installer is
; per-user and never elevated, which is not the case RedirectionGuard protects.
RedirectionGuard=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut to start MM Agent"; GroupDescription: "Shortcuts:"
Name: "autostart"; Description: "Start MM Agent automatically when I sign in to Windows (no setup needed again)"; GroupDescription: "Startup:"

[InstallDelete]
; Replaced by approve-chat.ps1 in 1.1.0.
Type: files; Name: "{app}\scripts\approve-telegram.ps1"

[Files]
Source: "..\scripts\*.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\*.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion isreadme
Source: "{#AppIcon}"; DestDir: "{app}"; Flags: ignoreversion

[Dirs]
Name: "{app}\logs"

[Icons]
; .cmd files have no icon of their own, so every shortcut points at the rooster icon.
Name: "{group}\Start MM Agent"; Filename: "{app}\Start-MM-Agent.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\{#AppIcon}"
Name: "{group}\Stop MM Agent"; Filename: "{app}\Stop-MM-Agent.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\{#AppIcon}"
Name: "{group}\Enter API Keys"; Filename: "{app}\Enter-API-Keys.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\{#AppIcon}"
Name: "{group}\Switch Model"; Filename: "{app}\Switch-Model.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\{#AppIcon}"
Name: "{group}\Connect Telegram"; Filename: "{app}\Connect-Telegram.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\{#AppIcon}"
Name: "{group}\Approve Telegram"; Filename: "{app}\Approve-Telegram.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\{#AppIcon}"
Name: "{group}\Connect WhatsApp"; Filename: "{app}\Connect-WhatsApp.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\{#AppIcon}"
Name: "{group}\Approve WhatsApp"; Filename: "{app}\Approve-WhatsApp.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\{#AppIcon}"
Name: "{group}\MM Agent Setup"; Filename: "{app}\Run-Setup.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\{#AppIcon}"
Name: "{group}\Read Me"; Filename: "{app}\README.md"
Name: "{group}\Uninstall MM Agent"; Filename: "{uninstallexe}"; IconFilename: "{app}\{#AppIcon}"
Name: "{autodesktop}\MM Agent"; Filename: "{app}\Start-MM-Agent.cmd"; WorkingDir: "{app}"; IconFilename: "{app}\{#AppIcon}"; Tasks: desktopicon
; Windows sign-in: start quietly in the background (no browser pages). Removed again on uninstall.
Name: "{userstartup}\MM Agent"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\scripts\start.ps1"" -Background"; \
  WorkingDir: "{app}"; IconFilename: "{app}\{#AppIcon}"; Comment: "Starts MM Agent in the background"; Tasks: autostart

[Run]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -NoExit -File ""{app}\scripts\first-run.ps1"""; \
  WorkingDir: "{app}"; \
  Description: "Set up MM Agent now (installs the latest Node.js, Hermes Agent and OpenClaw, then asks for your API keys)"; \
  Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\stop.ps1"""; \
  Flags: runhidden; RunOnceId: "StopMMAgent"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\logs"
