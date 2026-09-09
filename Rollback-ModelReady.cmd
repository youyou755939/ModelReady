@echo off
setlocal
cd /d "%~dp0"
echo ModelReady will remove only changes recorded during ModelReady 0.4+ installs.
echo Software that existed before installation and user files will be preserved.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0modelready.ps1" rollback -Yes
echo.
pause
