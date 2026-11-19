; برنامج تثبيت «الدورة المستندية» لويندوز (Inno Setup 6).
; يُبنى في سير العمل: tool/build_windows_installer.sh
; التثبيت للمستخدم الحالي دون صلاحيات مدير، حتى يتمكن البرنامج من تحديث نفسه بصمت.
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif
#ifndef IconFile
  #define IconFile "..\..\windows\runner\resources\app_icon.ico"
#endif
#define AppName "منظومة رصد"
#define AppExe "dc_app.exe"

[Setup]
AppId={{8F6C2B1E-4D3A-4B7E-9C21-5A7D3E9F0B42}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=مكتب الشؤون الهندسية - لجنة إعادة إعمار منطقة الصابري ووسط البلاد
VersionInfoVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\DocumentCycle
DefaultGroupName={#AppName}
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=dc-app-setup
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "ar"; MessagesFile: "compiler:Default.isl,Arabic.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall
