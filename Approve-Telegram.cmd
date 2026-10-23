@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\approve-chat.ps1" -Channel telegram %*
pause
