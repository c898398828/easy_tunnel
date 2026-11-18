@echo off
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0build_installer.ps1"
if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Build failed!
    pause
    exit /b %ERRORLEVEL%
)
