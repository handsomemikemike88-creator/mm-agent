# Changelog

## 1.1.0
- **WhatsApp support**: Connect WhatsApp (QR code, like WhatsApp Web) and Approve WhatsApp in the Start Menu.
- Setup now offers to connect Telegram and/or WhatsApp after the API keys (optional).
- One approve script for both chat apps.

## 1.0.9
- New rooster app icon on the installer, all shortcuts and the installed-apps list.

## 1.0.8
- Detects a half-finished Hermes update even when `hermes --version` still works, and repairs it.
- The Hermes dashboard failing to start no longer stops MM Agent.

## 1.0.7
- Reads Hermes' `.env` safely and rebuilds it if it was damaged or had grown huge.
- Replaces a damaged bridge key; keeps only the 5 newest settings backups.

## 1.0.6
- Finishes a half-finished Hermes update; replaces a leftover brain on start (`--replace`).

## 1.0.5
- Setup no longer fails when OpenClaw is already linked (OpenClaw 2026.10.6+).

## 1.0.4
- Fixes "os error 448": turns off Inno Setup's inherited RedirectionGuard, with a safety net.

## 1.0.3
- Checks that Hermes really runs, repairs it, and explains missing files.

## 1.0.2
- Hermes dashboard opens next to the chat page; progress display so long steps never look frozen.

## 1.0.1
- Installs the latest Node.js automatically; fixes "openclaw is not recognized".

## 1.0.0
- First release: one-click installer for Hermes Agent + OpenClaw with encrypted API keys and Telegram.
