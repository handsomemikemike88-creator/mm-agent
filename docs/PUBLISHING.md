# Publishing MM Agent on GitHub

A checklist for putting MM Agent on GitHub and offering the installer as a free download.

## 1. Create the repository

1. On GitHub: **+ → New repository**.
2. **Repository name**: `mm-agent`
3. **Description**: use the About text below.
4. **Public**. Don't add a README, .gitignore or license; this folder already has them.
5. Click **Create repository**.

## 2. Upload the code

The `.gitignore` keeps `logs/` (personal data) and `dist/` (big EXEs) out of the repository.
In PowerShell, inside the `MM Agent` folder:

```powershell
git init
git add .
git status          # check: no logs\ or dist\ files listed
git commit -m "MM Agent 1.1.0"
git branch -M main
git remote add origin https://github.com/YOUR-NAME/mm-agent.git
git push -u origin main
```

Or, without the command line: on the new repository page click **uploading an existing file** and drag in everything **except** the `logs` and `dist` folders.

## 3. Fill in the About box (right side of the repository page)

Click the ⚙ gear next to **About**:

- **Description**:
  > One-click Windows AI assistant: Hermes Agent as the brain, OpenClaw as the chat interface. Chat in your browser, on Telegram or on WhatsApp with DeepSeek, OpenAI, Claude or Kimi. Free, local, encrypted API keys.
- **Website**: leave empty, or your own page.
- **Topics** (type each one, press Enter):
  `ai-agent` `ai-assistant` `hermes-agent` `openclaw` `windows` `installer` `chatbot` `telegram-bot` `whatsapp-bot` `deepseek` `openai` `anthropic` `claude` `kimi` `llm` `local-first` `powershell` `inno-setup`
- Tick **Releases** so the latest download shows on the page.

## 4. Publish the installer (Releases)

1. Build it: `powershell -ExecutionPolicy Bypass -File installer\build-installer.ps1`
2. On GitHub: **Releases → Draft a new release**.
3. **Choose a tag**: `v1.1.0` (create new tag).
4. **Release title**: `MM Agent 1.1.0`
5. Paste the release notes below.
6. Drag in `dist\MM-Agent-Setup.exe`. Keep this exact name: the README's download link points to the latest release.
7. Click **Publish release**.

### Release notes (copy and paste)

```markdown
## MM Agent 1.1.0

**Download `MM-Agent-Setup.exe` below**, double-click it, and follow the setup window.

### New
- WhatsApp support: link with a QR code, approve who can chat.
- Setup offers to connect Telegram and/or WhatsApp after your API keys.
- New rooster app icon.

### Notes
- Windows may show "Windows protected your PC": click **More info → Run anyway** (the installer isn't code-signed).
- You need your own API key from DeepSeek, OpenAI, Anthropic or Kimi.
- Full history: see CHANGELOG.md.
```

## 5. Before every release

- [ ] Bump `AppVersion` in `installer\MM-Agent.iss`, and add the changes to `CHANGELOG.md`.
- [ ] Build, then test-install on a second PC if you can.
- [ ] `git status` shows no `logs\` or `dist\` files.
- [ ] Never upload: `%USERPROFILE%\.mm-agent\keys.env`, `%LOCALAPPDATA%\hermes\.env`, `%USERPROFILE%\.openclaw\` (keys, tokens, WhatsApp link).

## 6. Optional extras

- **Code signing**: a code-signing certificate removes the "Windows protected your PC" warning (paid, from a certificate authority).
- **Screenshot**: add a picture of the chat page to the README, e.g. `docs/screenshot.png`, below the title.
- **Issues**: turn on GitHub Issues so users can report problems. Ask them for a screenshot of MM Agent Setup's first lines.
