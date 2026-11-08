@echo off
rem Turn on voice messages: understand WhatsApp/Telegram voice notes and answer them with a voice note.
rem   Setup-Voice-Messages.cmd -Reply always    -> answer every message with voice too
rem   Setup-Voice-Messages.cmd -Reply off       -> understand voice notes, but answer with text only
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-voice.ps1" %*
pause
