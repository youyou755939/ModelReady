@echo off
setlocal
cd /d "%~dp0"

:menu
cls
echo ==================================================
echo ModelReady 0.4 - Mathematical Modeling Environment
echo ==================================================
echo 1. Check full environment
echo 2. Install base profile
echo 3. Install full profile
echo 4. Repair/update full profile
echo 5. Verify full profile
echo 6. Start JupyterLab
echo 7. Uninstall full Python environment
echo 8. Roll back all ModelReady-recorded changes
echo 0. Exit
echo.
set /p "MODELREADY_CHOICE=Choose an option: "

if "%MODELREADY_CHOICE%"=="1" call :run doctor full
if "%MODELREADY_CHOICE%"=="2" call :run install base -Yes
if "%MODELREADY_CHOICE%"=="3" call :run install full -Yes
if "%MODELREADY_CHOICE%"=="4" call :run repair full -Yes
if "%MODELREADY_CHOICE%"=="5" call :run verify full
if "%MODELREADY_CHOICE%"=="6" call :run launch full
if "%MODELREADY_CHOICE%"=="7" call :run uninstall full
if "%MODELREADY_CHOICE%"=="8" call :run rollback full -Yes
if "%MODELREADY_CHOICE%"=="0" exit /b 0
goto menu

:run
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0modelready.ps1" %1 -Profile %2 %3
echo.
pause
exit /b 0
