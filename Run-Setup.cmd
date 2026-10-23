@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\first-run.ps1" %*
pause
