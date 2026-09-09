@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0modelready.ps1" doctor -Profile full
set "MODELREADY_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %MODELREADY_EXIT%

