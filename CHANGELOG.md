# Changelog

## 1.1.7
- **Fixed: MM Agent and a second copy of OpenClaw/Hermes fighting each other** (chats stop answering, `logs\interface.log`
  full of "Another gateway ... already owns this state directory"). OpenClaw's own autostart (`OpenClaw Gateway` login
  item or task, added by `openclaw gateway install` / `openclaw doctor --fix`) and Hermes' `Hermes_Gateway` task (added
  by some Hermes updates) started their own copies, which took over the port while MM Agent kept restarting its own.
  At every start MM Agent now turns those autostarts off (moved to `logs\disabled-autostarts` / task disabled, nothing
  deleted) and stops a copy they already started. MM Agent alone starts and watches Hermes and OpenClaw.
- **Shorter daily update:** OpenClaw is now updated with npm directly. OpenClaw's own updater spent about 8 minutes on
  checks and then failed on most Windows PCs, so chats were down for about 20 minutes; now it is a few minutes.
  OpenClaw's updater is still tried if npm fails.
- **Fixed: the update ran again at every start** when Hermes reported "No newer release ... this checkout is newer";
  that now counts as up to date.

## 1.1.6
- **Voice messages** on WhatsApp and Telegram (Start Menu -> **Voice Messages**, also offered during setup):
  - MM Agent now **understands voice notes** in any language (Cantonese, English, Mandarin, ...). They are turned into text
    on this PC with whisper.cpp + Whisper large-v3-turbo: free, no API key, the audio never leaves the PC. With an NVIDIA
    graphics card a voice note takes about 1 second (CUDA build); otherwise the processor is used.
    Chinese comes out in Traditional characters with Cantonese words, as used in Hong Kong.
  - A voice note is **answered with a voice note** (plus the text). Microsoft's free voices, chosen from the reply's
    language: Cantonese (zh-HK) for Chinese, English for English, also Japanese and Korean. Set `"chinese": "mandarin"`
    in `%LOCALAPPDATA%\MM Agent Voice\voice.json` for a Mandarin voice.
  - `Setup-Voice-Messages.cmd -Reply always` answers every message with voice; `-Reply off` keeps answers as text.
  - Voice notes on WhatsApp need ffmpeg in `C:\Program Files\ffmpeg` (OpenClaw only trusts system folders), so
    the voice setup installs it there once; Windows asks for permission.
- **Fixed: every chat reply failing with "OpenClaw couldn't finish this reply"** after the brain restarted in the middle
  of a reply (e.g. the daily update). Newer Hermes blocks such a conversation (`unknown_execution`) until the lost turn
  is acknowledged. A new **brain healer** (started with MM Agent) checks every minute and clears it with Hermes' own
  `hermes sessions discard`, so conversations recover by themselves. Log: `logs\brain-healer.log`.
- **Security: chat apps no longer get the brain's PC tools.** Every chat (WhatsApp, Telegram, chat page) reaches Hermes
  through its API server, which gave it full tools: terminal, files, code, browser, memory and search across all chats.
  Anyone who could message the number could make the PC run commands or read another client's chat. Setup now sets
  `platform_toolsets.api_server: []` (unless you chose a list yourself); the Hermes dashboard keeps its tools.
- **The interface (OpenClaw) restarts itself** if it stops, like the brain already did.
- **Fixed: replies full of `<|DSML| calls>` text.** OpenClaw told the brain about tools it could not use, so DeepSeek
  wrote its raw tool-call markup into the chat. The brain model is now marked `compat.supportsTools: false`, so no
  tool descriptions are sent and replies are plain text.
- **Course answers** (new OpenClaw plugin `mm-course-info`, read-only, no tools): every chat gets the course documents
  from `%USERPROFILE%\.openclaw\workspace\rag\corpus` (`.md`/`.txt`, sections marked as internal notes left out) and
  customer-service rules (`openclaw-plugin\mm-course-info\rules.md`): answer only from the documents, in the client's
  language; a fixed polite reply when something is not in them; never recommend other courses; never reveal model,
  keys, files or links. Edit or add course files and the next reply uses them.

## 1.1.5
- **Automatic daily updates of Hermes Agent, OpenClaw and Node.js** (installer option, on by default): at the first
  Windows sign-in of the day, and every day at 04:00 for PCs left on (Task Scheduler task "MM Agent Daily Update").
  MM Agent stops, updates, and starts again by itself. A failed update never stops MM Agent from starting; it is tried
  again next time. Progress is written to `logs\update.log`.
- New Start Menu shortcut **Update MM Agent** to update right now.
- Fixes OpenClaw updates failing with `gateway-stop-unverified` (e.g. `/update` from WhatsApp): OpenClaw can't replace its
  files while running, so MM Agent's updater stops it first (and falls back to npm if OpenClaw's own updater refuses).
- A Hermes update that stops halfway is repaired automatically with the official installer.

## 1.1.4
- **Starts automatically when you sign in to Windows** (installer option, on by default). Setup is only ever needed once:
  after a restart MM Agent comes up by itself in the background - chat page, Telegram and WhatsApp keep working -
  without opening browser pages. Progress is written to `logs\autostart.log`.

## 1.1.3
- No more false red errors: normal progress messages from Hermes and OpenClaw (e.g. "Installing TUI dependencies…"
  after the Hermes dashboard builds) were shown by Windows PowerShell as red "NativeCommandError" blocks.
  MM Agent's windows and logs now show them as plain text.

## 1.1.2
- **Faster replies (about 2.5x: 11.8 s -> 4.7 s for a short question)**: DeepSeek now defaults to `deepseek-v4-flash`,
  Hermes reasoning to "low", and OpenClaw only relays (minimal tools, no workspace files, thinking off),
  cutting its instructions per message from ~47,600 to ~20,600 tokens. Pick `deepseek-v4-pro` in Switch Model for harder work.
- **The brain restarts itself**: if Hermes stops (e.g. "Restart Gateway" or an update in the Hermes dashboard),
  MM Agent starts it again within seconds instead of leaving the chat with "Couldn't connect to the AI service".

## 1.1.1
- When OpenClaw updates itself and stops with "uses schema version N ... run openclaw doctor --fix",
  Start now backs up OpenClaw's databases, runs `openclaw doctor --fix`, and starts the interface again.

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
