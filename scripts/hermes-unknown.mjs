// Print the Hermes sessions that are blocked by a "lost turn" (one id per line).
// When the brain restarts in the middle of a reply (daily update, crash, auto-restart), Hermes marks
// that turn "unknown" and refuses every later message in the session with "unknown_execution"
// until it is acknowledged with `hermes sessions discard`. Read-only: this never changes the database.
// Usage: node hermes-unknown.mjs <path to Hermes state.db> [--all]   (--all: list every pending turn)
import { DatabaseSync } from 'node:sqlite';
import { existsSync } from 'node:fs';

const dbPath = process.argv[2];
const all = process.argv.includes('--all');
if (!dbPath || !existsSync(dbPath)) process.exit(0);
try {
  const db = new DatabaseSync(dbPath, { readOnly: true });
  db.exec('PRAGMA busy_timeout = 3000');
  if (all) {
    const rows = db.prepare("SELECT target_session_id AS id, status, intent, substr(payload_json, 1, 160) AS payload FROM session_admissions WHERE status != 'terminal' ORDER BY seq").all();
    for (const r of rows) process.stdout.write(`${r.id}\t${r.status}\t${r.intent}\t${r.payload}\n`);
  } else {
    const rows = db.prepare("SELECT DISTINCT target_session_id AS id FROM session_admissions WHERE status = 'unknown'").all();
    for (const r of rows) process.stdout.write(r.id + '\n');
  }
  db.close();
} catch (e) {
  // Older Hermes without this table, or the database is busy: nothing to do this time.
  if (!/no such table/i.test(String(e))) console.error('hermes-unknown: ' + (e?.message ?? e));
}
