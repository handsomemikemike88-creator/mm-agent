@echo off
rem Update Node.js, OpenClaw and Hermes Agent now (even if it already ran today), then start MM Agent again.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\update-all.ps1" -Force -Restart %*
pause
