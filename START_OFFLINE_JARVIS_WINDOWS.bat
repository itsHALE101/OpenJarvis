@echo off
setlocal EnableExtensions
title JARVIS - Automatic Offline Setup

rem This file works by itself: no ZIP, folder search, or manual copying.
rem Download only two installer scripts from a pinned commit of your GitHub fork.
rem The official setup then installs a separate local OpenJarvis installation.
set "BOOTROOT=%LOCALAPPDATA%\OpenJarvis-Offline\bootstrap"
set "BOOTPS=%BOOTROOT%\jarvis_voice_setup\one_click_windows.ps1"
set "BOOTINSTALL=%BOOTROOT%\deploy\windows\install.ps1"
set "REVISION=4d50879ad774665e1fd62d3e91da36743b0f3530"

echo.
echo ============================================================
echo  JARVIS - FREE OFFLINE INSTALLATION
echo ============================================================
echo  This setup leaves your existing Jarvis application alone.
echo  It downloads free components on first install; no paid APIs.
echo  Windows may require the official C++ Build Tools installation.
echo.

if not exist "%BOOTROOT%\jarvis_voice_setup" mkdir "%BOOTROOT%\jarvis_voice_setup"
if not exist "%BOOTROOT%\deploy\windows" mkdir "%BOOTROOT%\deploy\windows"
if not exist "%BOOTROOT%\jarvis_voice_setup" goto failed
if not exist "%BOOTROOT%\deploy\windows" goto failed

echo [1/2] Recovering the installation files directly from your GitHub...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'; $base='https://raw.githubusercontent.com/itsHALE101/OpenJarvis/%REVISION%'; Invoke-WebRequest -UseBasicParsing -Uri ($base + '/jarvis_voice_setup/one_click_windows.ps1') -OutFile '%BOOTPS%'; Invoke-WebRequest -UseBasicParsing -Uri ($base + '/deploy/windows/install.ps1') -OutFile '%BOOTINSTALL%';"
if errorlevel 1 goto failed
if not exist "%BOOTPS%" goto failed
if not exist "%BOOTINSTALL%" goto failed

echo [2/2] Installing and starting the separate offline Jarvis...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%BOOTPS%"
if errorlevel 1 goto failed

echo.
echo [OK] Setup program exited normally. Check that Jarvis can speak.
echo To launch it again, use OPEN_OFFLINE_JARVIS_AGAIN.bat from your repo.
pause
exit /b 0

:failed
echo.
echo [ERROR] Setup did not complete. Please take a screenshot of this window.
echo Your existing Jarvis application has not been intentionally replaced.
pause
exit /b 1
