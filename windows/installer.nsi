; ============================================================================
; FreeCore VPN — Windows installer (NSIS)
; ----------------------------------------------------------------------------
; Запуск: makensis -DSOURCE_DIR=<path-to-Release> -DOUTPUT=<path-to-setup.exe>
;          installer.nsi
;
; Требуется NSIS 3.x (на github runner windows-latest установлен как
; `C:\Program Files (x86)\NSIS\makensis.exe`).
; ============================================================================

!define APP_NAME       "FreeCore VPN"
!define APP_BINARY     "FreeCoreVPN.exe"
!define APP_PUBLISHER  "FreeCore VPN"
!define APP_URL        "https://t.me/FreeCore_VPN_bot"
!define APP_REGKEY     "Software\Microsoft\Windows\CurrentVersion\Uninstall\FreeCoreVPN"

!ifndef VERSION
  !define VERSION "1.0.0"
!endif

!ifndef SOURCE_DIR
  !error "SOURCE_DIR is required (path to the flutter Release/ folder)"
!endif

!ifndef OUTPUT
  !define OUTPUT "FreeCoreVPN-Setup.exe"
!endif

Name        "${APP_NAME}"
OutFile     "${OUTPUT}"
InstallDir  "$PROGRAMFILES64\FreeCore VPN"
InstallDirRegKey HKLM "Software\FreeCoreVPN" "InstallDir"
RequestExecutionLevel admin    ; ставим в Program Files → нужен admin
Unicode true
SetCompressor /SOLID lzma

; Метаданные exe-установщика
VIProductVersion "${VERSION}.0"
VIAddVersionKey  "ProductName"     "${APP_NAME}"
VIAddVersionKey  "CompanyName"     "${APP_PUBLISHER}"
VIAddVersionKey  "FileDescription" "${APP_NAME} Setup"
VIAddVersionKey  "FileVersion"     "${VERSION}"
VIAddVersionKey  "ProductVersion"  "${VERSION}"
VIAddVersionKey  "LegalCopyright"  "Copyright (C) 2026 FreeCore VPN. Built on Hiddify (GPL-3.0)."

!include "MUI2.nsh"

; Иконка установщика — берём ту что сгенерил flutter_launcher_icons.
!define MUI_ICON   "..\windows\runner\resources\app_icon.ico"
!define MUI_UNICON "..\windows\runner\resources\app_icon.ico"

!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_BINARY}"
!define MUI_FINISHPAGE_RUN_TEXT "Запустить FreeCore VPN"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Russian"
!insertmacro MUI_LANGUAGE "English"

; ----------------------------------------------------------------------------

Section "FreeCore VPN" SecMain
  SectionIn RO

  ; Snap прежнего инстанса (на случай переустановки)
  ExecWait 'taskkill /F /IM "${APP_BINARY}" /T' $0

  SetOutPath "$INSTDIR"
  ; Копируем ВСЁ содержимое Release/ (флаттеровский билд)
  File /r "${SOURCE_DIR}\*.*"

  ; Ярлык в меню Пуск
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortCut  "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_BINARY}"
  CreateShortCut  "$SMPROGRAMS\${APP_NAME}\Удалить.lnk"     "$INSTDIR\Uninstall.exe"

  ; Ярлык на Рабочем столе
  CreateShortCut  "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_BINARY}"

  ; Запись в "Программы и компоненты" (Add/Remove Programs)
  WriteRegStr HKLM "${APP_REGKEY}" "DisplayName"     "${APP_NAME}"
  WriteRegStr HKLM "${APP_REGKEY}" "DisplayVersion"  "${VERSION}"
  WriteRegStr HKLM "${APP_REGKEY}" "Publisher"       "${APP_PUBLISHER}"
  WriteRegStr HKLM "${APP_REGKEY}" "URLInfoAbout"    "${APP_URL}"
  WriteRegStr HKLM "${APP_REGKEY}" "DisplayIcon"     "$INSTDIR\${APP_BINARY}"
  WriteRegStr HKLM "${APP_REGKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${APP_REGKEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKLM "${APP_REGKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${APP_REGKEY}" "NoRepair" 1

  WriteRegStr HKLM "Software\FreeCoreVPN" "InstallDir" "$INSTDIR"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
SectionEnd

; ----------------------------------------------------------------------------

Section "Uninstall"
  ExecWait 'taskkill /F /IM "${APP_BINARY}" /T' $0

  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\Удалить.lnk"
  RMDir  "$SMPROGRAMS\${APP_NAME}"

  ; Очищаем установочный каталог целиком (вкл. встроенный sing-box, профили)
  RMDir /r "$INSTDIR"

  DeleteRegKey HKLM "${APP_REGKEY}"
  DeleteRegKey HKLM "Software\FreeCoreVPN"
SectionEnd
