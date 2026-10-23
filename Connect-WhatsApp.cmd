@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\connect-whatsapp.ps1" %*
pause
