@echo off
rem Builds the Microsoft Store MSIX package (unsigned - the Store signs it).
rem Needs msix_config in pubspec.yaml filled in from Partner Center (incl. publisher).
rem Before each Store upload raise msix_version in pubspec.yaml (last number stays 0).
rem Developer Mode must be on (pdfrx uses symlinks during the Windows build).
rem Local test package instead (self-signed, installs a test certificate):
rem   dart run msix:create

cd /d "%~dp0"
call flutter pub get
call dart run msix:create --store
if errorlevel 1 (
  echo.
  echo MSIX build FAILED.
  pause
  exit /b 1
)
echo.
echo Done: build\windows\x64\runner\Release\calibre_touch.msix
pause
