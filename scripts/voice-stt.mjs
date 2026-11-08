// MM Agent speech-to-text for OpenClaw (tools.media.models CLI entry).
// Usage: node voice-stt.mjs <audio file>   -> prints the transcript on stdout.
// WhatsApp/Telegram voice notes are Ogg/Opus: ffmpeg turns them into 16 kHz mono WAV, then
// whisper.cpp (local, free, nothing leaves the PC) transcribes them in whatever language was spoken.
// Paths come from voice.json, written by install-voice.ps1.
import { spawnSync } from 'node:child_process';
import { readFileSync, rmSync, mkdtempSync, statSync } from 'node:fs';
import { tmpdir, cpus } from 'node:os';
import { join } from 'node:path';

const input = process.argv[2];
if (!input) { console.error('usage: node voice-stt.mjs <audio file>'); process.exit(2); }

const cfgPath = process.env.MM_VOICE_CONFIG || join(process.env.LOCALAPPDATA || '', 'MM Agent Voice', 'voice.json');
const cfg = JSON.parse(readFileSync(cfgPath, 'utf8').replace(/^﻿/, ''));
// A short Cantonese sentence steers Whisper to Traditional Chinese with Cantonese words (as used in
// Hong Kong) instead of Simplified Mandarin; English and other languages are not affected (tested).
const prompt = cfg.prompt ?? '你好，歡迎查詢。我哋嘅課程好受歡迎，有咩可以幫到你？';

const work = mkdtempSync(join(tmpdir(), 'mm-stt-'));
try {
  const wav = join(work, 'voice.wav');
  const ff = spawnSync(cfg.ffmpeg, ['-hide_banner', '-loglevel', 'error', '-y', '-i', input,
    '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', wav], { encoding: 'utf8', windowsHide: true });
  if (ff.status !== 0) { console.error('ffmpeg failed: ' + (ff.stderr || ff.error)); process.exit(1); }

  const args = ['-m', cfg.model, '-l', cfg.language || 'auto', '-nt', '-np', '-f', wav];
  if (prompt) args.push('--prompt', prompt);
  if (!cfg.gpu) {
    // CPU only: use the physical cores, and only as much audio context as the clip needs
    // (a 10-second voice note then costs about a third of the full 30-second window).
    args.push('-t', String(Math.max(4, Math.min(16, Math.floor(cpus().length / 2)))));
    const seconds = Math.max(0, (statSync(wav).size - 44) / 32000);
    if (seconds < 28) args.push('-ac', String(Math.min(1500, Math.ceil((seconds + 2) / 30 * 1500 / 64) * 64)));
  }
  const w = spawnSync(cfg.whisper, args, { encoding: 'utf8', windowsHide: true, maxBuffer: 4 * 1024 * 1024 });
  if (w.status !== 0) { console.error('whisper failed: ' + (w.stderr || w.error)); process.exit(1); }
  const text = (w.stdout || '').split(/\r?\n/).map(s => s.trim()).filter(Boolean).join(' ').trim();
  process.stdout.write(text + '\n');
} finally {
  rmSync(work, { recursive: true, force: true });
}
