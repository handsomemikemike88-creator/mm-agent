// MM Agent text-to-speech for OpenClaw (tts provider "tts-local-cli").
// Usage: node voice-tts.mjs <output.mp3> <text...>
// Picks the voice from the reply's language, so the client hears their own language:
//   Chinese -> Cantonese (zh-HK) by default; voice.json "chinese": "mandarin" for Mandarin, or
//   "auto" (Simplified -> Mandarin, Traditional/Cantonese words -> Cantonese).
//   Japanese -> ja-JP, Korean -> ko-KR, anything else -> English.
// Uses Microsoft's free Edge voices (no API key). OpenClaw converts the MP3 into a WhatsApp voice note.
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

let argv = process.argv.slice(2);
const opus = argv[0] === '--opus';          // OpenClaw config passes --opus with outputFormat "opus"
if (opus) argv = argv.slice(1);
const [out, ...rest] = argv;
const text = rest.join(' ').trim();
if (!out || !text) { console.error('usage: node voice-tts.mjs <output.mp3> <text>'); process.exit(2); }

const cfgPath = process.env.MM_VOICE_CONFIG || join(process.env.LOCALAPPDATA || '', 'MM Agent Voice', 'voice.json');
const cfg = JSON.parse(readFileSync(cfgPath, 'utf8').replace(/^﻿/, ''));
const voices = Object.assign({
  cantonese: ['zh-HK-HiuMaanNeural', 'zh-HK'],
  mandarin: ['zh-CN-XiaoxiaoNeural', 'zh-CN'],
  japanese: ['ja-JP-NanamiNeural', 'ja-JP'],
  korean: ['ko-KR-SunHiNeural', 'ko-KR'],
  english: ['en-US-AvaMultilingualNeural', 'en-US'],
}, cfg.voices || {});

function pickVoice(s) {
  const count = re => (s.match(re) || []).length;
  const kana = count(/[぀-ヿ]/g);
  const hangul = count(/[가-힯]/g);
  const han = count(/[㐀-鿿]/g);
  const latin = count(/[A-Za-z]/g);
  if (kana > 0 && kana * 4 >= han) return 'japanese';
  if (hangul > latin / 3 && hangul > han) return 'korean';
  if (han * 3 >= latin) {
    if ((cfg.chinese || 'cantonese') !== 'auto') return cfg.chinese === 'mandarin' ? 'mandarin' : 'cantonese';
    // Characters that exist only in Simplified or only in Traditional Chinese.
    const simp = count(/[们这说为时会对发过还没问题么样经现开关见长门东车书买卖国学习听语话认让请谢电脑网页钱个来吗后里给从应该点业务课报费]/g);
    const trad = count(/[們這說為時會對發過還沒問題麼樣經現開關見長門東車書買賣國學習聽語話認讓請謝電腦網頁錢個來嗎後裡給從應該點業務課報費]/g);
    // Cantonese-only words also mean Cantonese.
    const yue = count(/[嘅咗喺唔佢哋冇嚟啲咁乜嘢噉睇俾㗎啱]/g);
    return (simp > trad && yue === 0) ? 'mandarin' : 'cantonese';
  }
  return 'english';
}

const [voice, lang] = voices[cfg.forceVoice || pickVoice(text)];
const mod = await import(pathToFileURL(cfg.edgeTts).href);
const EdgeTTS = mod.EdgeTTS || (mod.default && mod.default.EdgeTTS);
const tts = new EdgeTTS({ voice, lang, outputFormat: 'audio-24khz-48kbitrate-mono-mp3', timeout: 60000 });

// OpenClaw asks for Ogg/Opus (outputFormat "opus"): that is what WhatsApp and Telegram voice notes
// are, so make it here with ffmpeg rather than relying on a later conversion.
if (opus || /\.(ogg|opus)$/i.test(out)) {
  const work = mkdtempSync(join(tmpdir(), 'mm-tts-'));
  try {
    const mp3 = join(work, 'speech.mp3');
    await tts.ttsPromise(text, mp3);
    const ff = spawnSync(cfg.ffmpeg, ['-hide_banner', '-loglevel', 'error', '-y', '-i', mp3,
      '-ar', '48000', '-ac', '1', '-c:a', 'libopus', '-b:a', '64k', '-f', 'ogg', out], { encoding: 'utf8', windowsHide: true });
    if (ff.status !== 0) { console.error('ffmpeg failed: ' + (ff.stderr || ff.error)); process.exit(1); }
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
} else {
  await tts.ttsPromise(text, out);
}
console.error(`voice: ${voice}`);
