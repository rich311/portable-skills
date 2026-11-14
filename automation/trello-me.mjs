#!/usr/bin/env node
// Prints the Trello member the project's Trello MCP server is logged in as:
// {"id":"...","username":"...","fullName":"..."}
//
// For Trello MCP servers with no get_me tool. Keys come from TRELLO_API_KEY /
// TRELLO_TOKEN in the environment (cloud sessions), otherwise from the env of
// the MCP server named TRELLO_MCP_SERVER (default "trello") in
// ~/.claude.json. The keys are never printed.

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const serverName = process.env.TRELLO_MCP_SERVER || "trello";

function findServerEnv(node) {
  if (!node || typeof node !== "object") return null;
  if (node[serverName]?.env?.TRELLO_TOKEN) return node[serverName].env;
  for (const value of Object.values(node)) {
    const found = findServerEnv(value);
    if (found) return found;
  }
  return null;
}

let key = process.env.TRELLO_API_KEY;
let token = process.env.TRELLO_TOKEN;
if (!key || !token) {
  try {
    const env = findServerEnv(JSON.parse(readFileSync(join(homedir(), ".claude.json"), "utf8")));
    key ||= env?.TRELLO_API_KEY;
    token ||= env?.TRELLO_TOKEN;
  } catch {
    // fall through to the error below
  }
}
if (!key || !token) {
  console.error(`trello-me: no TRELLO_API_KEY/TRELLO_TOKEN in the environment or the "${serverName}" MCP config`);
  process.exit(1);
}

const url = new URL("https://api.trello.com/1/members/me");
url.search = new URLSearchParams({ fields: "id,username,fullName", key, token }).toString();
const res = await fetch(url);
if (!res.ok) {
  console.error(`trello-me: Trello returned ${res.status}`);
  process.exit(1);
}
const { id, username, fullName } = await res.json();
console.log(JSON.stringify({ id, username, fullName }));
