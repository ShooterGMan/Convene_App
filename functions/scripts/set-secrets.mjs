// One-time migration helper: pushes each production secret from functions/.env
// into Firebase/Google Secret Manager, so the Cloud Functions (which declare
// runWith({ secrets: [...] })) can be deployed and read them at runtime.
//
// Usage (from the functions/ directory, after `firebase login` and selecting
// the right project with `firebase use`):
//
//     node scripts/set-secrets.mjs
//
// It reads values only from functions/.env locally and streams each to the
// Firebase CLI over stdin — no secret value is printed or written anywhere.
//
// NOTE: `firebase functions:secrets:set` can throw a harmless "unexpected
// error" in a post-creation step (notably on Windows) *after* the secret
// version has already been written. So this script does NOT trust the set
// command's exit code — it verifies each secret afterwards by reading it back
// with `functions:secrets:access` (value captured, never printed).
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const envPath = fileURLToPath(new URL("../.env", import.meta.url));

let raw;
try {
  raw = readFileSync(envPath, "utf8");
} catch {
  console.error(`Could not read ${envPath}. Run this from the functions/ directory and make sure functions/.env exists.`);
  process.exit(1);
}

// Minimal .env parse: split on the FIRST '=' only (values like the service
// account JSON / base64 private key can themselves contain '='), and strip a
// single pair of surrounding quotes if present.
const env = {};
for (const line of raw.split(/\r?\n/)) {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith("#")) continue;
  const eq = trimmed.indexOf("=");
  if (eq === -1) continue;
  const key = trimmed.slice(0, eq).trim();
  let val = trimmed.slice(eq + 1).trim();
  if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
    val = val.slice(1, -1);
  }
  env[key] = val;
}

// These 6 are referenced by runWith({ secrets }) in livekit.ts + webhook.ts.
// ENABLE_SPEAKER_TRACKS is a non-secret flag and is intentionally NOT included.
const KEYS = [
  "LIVEKIT_API_KEY",
  "LIVEKIT_API_SECRET",
  "LIVEKIT_HOST",
  "GEMINI_API_KEY",
  "EGRESS_BUCKET",
  "GCP_EGRESS_CREDENTIALS",
];

const missing = KEYS.filter((k) => !env[k]);
if (missing.length) {
  console.error(`Missing values in functions/.env: ${missing.join(", ")}`);
  process.exit(1);
}

// Reads a secret back and returns its current value (or null). Output is
// captured, never inherited, so the value is not printed to the terminal.
function readSecret(key) {
  try {
    const out = execFileSync("firebase", ["functions:secrets:access", `${key}@latest`], {
      stdio: ["ignore", "pipe", "ignore"],
      shell: true,
    });
    const v = out.toString().replace(/\r?\n$/, "");
    return v.length > 0 ? v : null;
  } catch {
    return null;
  }
}

const results = [];
for (const key of KEYS) {
  process.stdout.write(`Setting ${key} ... `);
  try {
    execFileSync("firebase", ["functions:secrets:set", key, "--data-file", "-"], {
      input: env[key],
      // Swallow the CLI's chatter/harmless post-error; verification is the
      // source of truth below.
      stdio: ["pipe", "ignore", "ignore"],
      shell: true,
    });
  } catch {
    // Ignored on purpose — the version is often created before the throw.
  }
  // Verify by reading it back and comparing to what we intended to store.
  const stored = readSecret(key);
  const ok = stored !== null && stored === env[key];
  results.push({ key, ok, present: stored !== null });
  console.log(ok ? "ok" : stored !== null ? "MISMATCH" : "NOT SET");
}

console.log("\nSummary:");
for (const r of results) {
  console.log(`  [${r.ok ? "OK" : r.present ? "MISMATCH" : "NOT SET"}] ${r.key}`);
}

const allOk = results.every((r) => r.ok);
if (allOk) {
  console.log("\nAll 6 secrets verified. Next: firebase deploy --only functions");
  process.exit(0);
} else {
  console.log("\nSome secrets are not set correctly. Re-run this script, or set the failing ones manually:");
  console.log("  firebase functions:secrets:set <NAME>");
  process.exit(1);
}
