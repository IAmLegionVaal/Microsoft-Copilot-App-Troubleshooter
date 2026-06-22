@echo off
setlocal
cd /d "%~dp0"

:menu
cls
echo ============================================================
echo   MICROSOFT COPILOT REPAIR TOOLKIT
echo ============================================================
echo   1. Diagnose only
echo   2. Run safe repair set
echo   3. Restart Copilot
echo   4. Reset Copilot cache
echo   5. Reset Copilot app package
echo   6. Re-register Copilot app package
echo   7. Flush DNS cache
echo   0. Exit
echo ============================================================
set /p CHOICE=Select an option: 

if "%CHOICE%"=="1" set ACTION=Diagnose&goto run
if "%CHOICE%"=="2" set ACTION=RepairAllSafe&goto run
if "%CHOICE%"=="3" set ACTION=RestartApp&goto run
if "%CHOICE%"=="4" set ACTION=ResetCache&goto run
if "%CHOICE%"=="5" set ACTION=ResetAppPackage&goto run
if "%CHOICE%"=="6" set ACTION=ReregisterAppPackage&goto run
if "%CHOICE%"=="7" set ACTION=FlushDns&goto run
if "%CHOICE%"=="0" goto end
goto menu

:run
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath '%~dp0Repair.ps1' -ErrorAction SilentlyContinue; & '%~dp0Repair.ps1' -Action '%ACTION%'"
echo.
pause
goto menu

:end
endlocal
