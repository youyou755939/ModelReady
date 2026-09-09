@echo off
setlocal
cd /d "%~dp0"
echo ModelReady will install the full mathematical-modeling environment.
echo A verification report will be generated after installation.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0modelready.ps1" install -Profile full -Yes
set "MODELREADY_EXIT=%ERRORLEVEL%"
echo.
if not "%MODELREADY_EXIT%"=="0" echo Installation did not complete successfully. Review the messages above.
if "%MODELREADY_EXIT%"=="0" echo ModelReady installation and verification finished.
pause
exit /b %MODELREADY_EXIT%

