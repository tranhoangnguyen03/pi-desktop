#!/usr/bin/env node
// Fork-only. Upstream's architecture check caps the length of large files, and upstream
// re-fits those caps to its own code. The fork patch adds a few lines to some capped
// files, so after each upstream merge this raises a cap only where:
//   - the file is over its cap, and
//   - the fork patch changes that file relative to upstream.
// Usage: node .github/fork/fit-line-budgets.mjs <upstream-commit>
import { execFileSync } from "node:child_process";
import fs from "node:fs";

const upstream = process.argv[2];
if (!upstream) throw new Error("usage: fit-line-budgets.mjs <upstream-commit>");

const policyPath = "scripts/architecture-policy.mjs";
const forkFiles = new Set(
  execFileSync("git", ["diff", "--name-only", upstream, "HEAD"], { encoding: "utf8" }).split("\n").filter(Boolean),
);

let report = "";
try {
  execFileSync("node", ["scripts/check-architecture.mjs"], { encoding: "utf8", stdio: "pipe" });
} catch (error) {
  report = `${error.stdout ?? ""}${error.stderr ?? ""}`;
  console.log(report.trim());
}

let policy = fs.readFileSync(policyPath, "utf8");
const raised = [];
for (const [, file, lines, cap] of report.matchAll(/^- (\S+): (\d+) lines exceeds baseline (\d+)$/gm)) {
  if (!forkFiles.has(file)) continue;
  const entry = new RegExp(`("${file.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}": \\{\\s*maxLines: )${cap}\\b`);
  if (!entry.test(policy)) throw new Error(`Cannot find the ${cap}-line budget for ${file} in ${policyPath}`);
  policy = policy.replace(entry, `$1${lines}`);
  raised.push(`${file}: ${cap} -> ${lines}`);
}

if (raised.length > 0) {
  fs.writeFileSync(policyPath, policy);
  console.log(`Raised line budgets for the fork patch:\n${raised.map((line) => `  ${line}`).join("\n")}`);
} else {
  console.log("No line budgets needed raising.");
}
