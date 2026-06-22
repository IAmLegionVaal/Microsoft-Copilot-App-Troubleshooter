@echo off
setlocal
cd /d "%~dp0"

:menu
set "ACTION="
cls
echo ============================================================
echo   MICROSOFT COPILOT REPAIR TOOLKIT
echo ============================================================
echo   1. Diagnose only
echo   2. Run safe repair set
echo   3. Restart Copilot
echo   4. Rebuild Copilot cache
echo   5. Repair Copilot application package
echo   6. Re-register Copilot application package
echo   7. Flush DNS cache
echo   0. Exit
echo ============================================================
set /p CHOICE=Select an option: 

if "%CHOICE%"=="1" set "ACTION=Diagnose"
if "%CHOICE%"=="2" set "ACTION=RepairAllSafe"
if "%CHOICE%"=="3" set "ACTION=RestartApp"
if "%CHOICE%"=="4" set "ACTION=ResetCache"
if "%CHOICE%"=="5" set "ACTION=ResetAppPackage"
if "%CHOICE%"=="6" set "ACTION=ReregisterAppPackage"
if "%CHOICE%"=="7" set "ACTION=FlushDns"
if "%CHOICE%"=="0" goto end
if not defined ACTION goto menu

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Repair.ps1" -Action "%ACTION%"
echo.
pause
goto menu

:end
endlocal
