@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\enter-api-keys.ps1" %*
pause
