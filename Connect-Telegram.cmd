@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\connect-telegram.ps1" %*
pause
