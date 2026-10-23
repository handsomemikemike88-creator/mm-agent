@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\switch-model.ps1" %*
pause
