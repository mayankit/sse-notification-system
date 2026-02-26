@echo off
REM #######################################################################
REM # SSE Notification System - Local Setup Script for Windows (Batch)
REM # Run as Administrator: Right-click -> Run as Administrator
REM #######################################################################

echo.
echo ===============================================================
echo   SSE Notification System - Local Setup (Windows)
echo ===============================================================
echo.

REM Check for admin rights
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: This script must be run as Administrator
    echo Right-click this file and select "Run as Administrator"
    pause
    exit /b 1
)

REM Check if PowerShell is available
where powershell >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: PowerShell is required but not found
    pause
    exit /b 1
)

echo Launching PowerShell setup script...
echo.

REM Get the directory of this script
set SCRIPT_DIR=%~dp0

REM Run the PowerShell script
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%setup-local.ps1"

if %errorLevel% neq 0 (
    echo.
    echo ERROR: Setup failed. Please check the error messages above.
    pause
    exit /b 1
)

echo.
echo Setup completed successfully!
pause
