#!/usr/bin/env node
/**
 * Start a GitHub Actions workflow, wait for it, and print its RESULT: lines.
 * Cloud sessions use it to reach things only GitHub holds secrets for (production
 * migrations, the report email). Copy it into the project, e.g. scripts/gh-workflow.mjs.
 *
 *   node scripts/gh-workflow.mjs apply-prod-migrations.yml expected="2026..._x.sql" apply=false card=12
 *   node scripts/gh-workflow.mjs email-report.yml subject="Triage: ..." body=@/tmp/report.txt
 *
 * Env:
 *   GH_ACTIONS_TOKEN or GITHUB_PAT  fine-grained token, this repo: Actions read/write
 *                                   (plus Checks read to see result annotations)
 *   GH_REPO                         <owner>/<repo> (default: parsed from `git remote get-url origin`)
 *   GH_REF                          branch to run the workflow from (default: main)
 * The env file (ENV_FILE, default .env.local) is loaded first when present.
 *
 * A value starting with @ is read from that file. Exit 0 when the run succeeds, 1 otherwise.
 * Workflows should print `::notice title=RESULT::<text>`: annotations come from api.github.com,
 * which cloud networks reach; job logs redirect to a storage host they often block.
 * Never prints the token.
 */
import { readFileSync, existsSync } from "node:fs";
import { execSync } from "node:child_process";

const envFile = process.env.ENV_FILE || ".env.local";
if (existsSync(envFile) && typeof process.loadEnvFile === "function") {
  try { process.loadEnvFile(envFile); } catch { /* fall back to the environment */ }
}
function repoFromGit() {
  try {
    const url = execSync("git remote get-url origin", { encoding: "utf8" }).trim();
    return url.match(/github\.com[:/]([^/]+\/[^/.]+?)(?:\.git)?$/)?.[1];
  } catch { return undefined; }
}
const REPO = process.env.GH_REPO || repoFromGit();
const REF = process.env.GH_REF || "main";
const API = `https://api.github.com/repos/${REPO}`;
const TIMEOUT_MS = 30 * 60_000;
const POLL_MS = 10_000;

const token = process.env.GH_ACTIONS_TOKEN || process.env.GITHUB_PAT;
const [workflow, ...pairs] = process.argv.slice(2);
if (!workflow) {
  console.error("usage: gh-workflow.mjs <workflow.yml> [key=value | key=@file]...");
  process.exit(2);
}
if (!REPO) { console.error("❌ Couldn't tell the repo: set GH_REPO=<owner>/<repo>."); process.exit(1); }
if (!token) {
  console.error("❌ No GitHub token: set GITHUB_PAT in the cloud environment (fine-grained, Actions read/write on this repo).");
  process.exit(1);
}

const inputs = {};
for (const p of pairs) {
  const i = p.indexOf("=");
  if (i < 1) { console.error(`bad argument: ${p}`); process.exit(2); }
  const v = p.slice(i + 1);
  inputs[p.slice(0, i)] = v.startsWith("@") ? readFileSync(v.slice(1), "utf8") : v;
}

const headers = {
  Authorization: `Bearer ${token}`,
  Accept: "application/vnd.github+json",
  "X-GitHub-Api-Version": "2022-11-28",
  "User-Agent": "gh-workflow-script",
};
async function gh(path, init = {}) {
  const res = await fetch(path.startsWith("http") ? path : `${API}${path}`, { ...init, headers: { ...headers, ...init.headers } });
  if (!res.ok) throw new Error(`GitHub ${init.method ?? "GET"} ${path}: ${res.status} ${(await res.text()).slice(0, 300)}`);
  return res;
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const started = Date.now();
await gh(`/actions/workflows/${workflow}/dispatches`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ ref: REF, inputs }),
});

// The run this dispatch created: the newest workflow_dispatch run created after we started.
let run;
for (let i = 0; i < 30 && !run; i++) {
  await sleep(i === 0 ? 3000 : 5000);
  const { workflow_runs } = await (await gh(`/actions/workflows/${workflow}/runs?event=workflow_dispatch&branch=${encodeURIComponent(REF)}&per_page=10`)).json();
  run = workflow_runs.find((r) => Date.parse(r.created_at) >= started - 5000);
}
if (!run) { console.error(`❌ Started ${workflow} but couldn't find its run`); process.exit(1); }
console.log(`run: ${run.html_url}`);

while (run.status !== "completed") {
  if (Date.now() - started > TIMEOUT_MS) { console.error(`❌ ${workflow} still running after 30 minutes: ${run.html_url}`); process.exit(1); }
  await sleep(POLL_MS);
  run = await (await gh(`/actions/runs/${run.id}`)).json();
}

const { jobs } = await (await gh(`/actions/runs/${run.id}/jobs`)).json();
let printed = false;
for (const job of jobs) {
  try {
    const notes = await (await gh(`/check-runs/${job.id}/annotations?per_page=50`)).json();
    for (const a of notes) {
      if (a.title === "RESULT") { console.log(`RESULT: ${a.message.trim()}`); printed = true; }
    }
  } catch (e) {
    console.error(`couldn't read the annotations for job ${job.name}: ${e.message}`);
  }
  if (printed) continue;
  try {
    const log = await (await gh(`/actions/jobs/${job.id}/logs`)).text();
    for (const line of log.split("\n")) {
      const m = line.match(/RESULT: .*/);
      if (m && !line.includes("echo") && !line.includes("print(")) { console.log(m[0].trim()); printed = true; }
    }
  } catch (e) {
    console.error(`couldn't read the log for job ${job.name}: ${e.message}`);
  }
}
// Workflows should only succeed when their result is good, so the conclusion alone is safe to act on.
if (!printed) {
  console.log(`RESULT: detail unreadable from here, run ${run.conclusion === "success" ? "succeeded" : "did not succeed"}: ${run.html_url}`);
}
console.log(`conclusion: ${run.conclusion}`);
process.exit(run.conclusion === "success" ? 0 : 1);
