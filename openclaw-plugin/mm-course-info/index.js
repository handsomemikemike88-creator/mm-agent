// mm-course-info: gives MM Agent your course information and customer-service rules on every chat.
//
// Before each reply OpenClaw asks this plugin for extra instructions ("before_prompt_build"). It
// returns the customer-service rules (rules.md, next to this file) plus the text of every course
// document in the course folder (*.md / *.txt), with sections marked as internal notes removed.
// No tools, no commands, no network: it only reads those files. Edit or add course files and the
// next reply uses them (files are re-read when they change).
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const DEFAULT_COURSE_DIR = join(homedir(), ".openclaw", "workspace", "rag", "corpus");
const MAX_CHARS = 40000; // keep the prompt bounded even if many files are added

// Sections whose heading contains one of these are internal and never shown to clients.
const INTERNAL_HEADING = /內部備註|内部备注|internal note|待補充資料|INTERNAL/i;

let cache = { key: "", text: "" };

function stripInternal(md) {
  const out = [];
  let skipLevel = 0;
  for (const line of md.split(/\r?\n/)) {
    const h = /^(#{1,6})\s+(.*)$/.exec(line);
    if (h) {
      const level = h[1].length;
      if (skipLevel && level <= skipLevel) skipLevel = 0;
      if (!skipLevel && INTERNAL_HEADING.test(h[2])) { skipLevel = level; continue; }
    }
    if (!skipLevel) out.push(line);
  }
  return out.join("\n")
    // Drop references to file names: clients must never see them (and they mean nothing to them).
    .replace(/[（(]?見\s*`[^`]+`[^）)\n]*[）)]?/g, "")
    .replace(/`[^`]+\.(md|txt|docx|pdf)`/g, "")
    .replace(/^來源：.*$/gm, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

// Your own rules (e.g. with the owner's number) win over the generic ones shipped with MM Agent.
const USER_RULES = join(homedir(), ".openclaw", "mm-course-rules.md");

function loadKnowledge(courseDir) {
  const rulesPath = existsSync(USER_RULES) ? USER_RULES : join(HERE, "rules.md");
  const files = existsSync(courseDir)
    ? readdirSync(courseDir).filter((f) => /\.(md|txt)$/i.test(f)).sort()
    : [];
  const key = [rulesPath, ...files.map((f) => join(courseDir, f))]
    .map((p) => { try { return p + ":" + statSync(p).mtimeMs; } catch { return p + ":missing"; } })
    .join("|");
  if (key === cache.key) return cache.text;

  const rules = existsSync(rulesPath) ? readFileSync(rulesPath, "utf8").trim() : "";
  const docs = files.map((f) => stripInternal(readFileSync(join(courseDir, f), "utf8"))).filter(Boolean);
  let text = [
    rules,
    "# 課程資料（官方，唯一可以引用嘅資料來源）",
    docs.length ? docs.join("\n\n---\n\n") : "（暫時未有任何課程資料。）",
  ].filter(Boolean).join("\n\n");
  if (text.length > MAX_CHARS) text = text.slice(0, MAX_CHARS) + "\n…";
  cache = { key, text };
  return text;
}

export default {
  id: "mm-course-info",
  name: "MM Agent course info",
  description: "Adds the course documents and customer-service rules to every MM Agent chat (read-only, no tools).",
  get configSchema() {
    return {
      safeParse(value) {
        if (value === undefined) return { success: true, data: undefined };
        if (!value || typeof value !== "object" || Array.isArray(value)) {
          return { success: false, error: { issues: [{ path: [], message: "expected config object" }] } };
        }
        return { success: true, data: value };
      },
    };
  },
  register(api) {
    const cfg = api.pluginConfig || {};
    const courseDir = typeof cfg.courseDir === "string" && cfg.courseDir ? cfg.courseDir : DEFAULT_COURSE_DIR;
    const agents = Array.isArray(cfg.agents) && cfg.agents.length ? cfg.agents : ["mm-agent"];
    api.on("before_prompt_build", (_event, ctx) => {
      if (ctx && ctx.agentId && !agents.includes(ctx.agentId)) return;
      try {
        return { appendSystemContext: loadKnowledge(courseDir) };
      } catch (err) {
        api.logger?.warn?.(`mm-course-info: could not read course files: ${err?.message ?? err}`);
      }
    });
  },
};
