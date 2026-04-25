#!/usr/bin/env node
// Tiny launcher that runs src/cli.ts via the local tsx, so we don't need a
// separate compile step. Works on macOS/Linux/Windows (npm rewrites the .bin
// entry to a platform-appropriate script).

import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { existsSync } from "node:fs";

const here = dirname(fileURLToPath(import.meta.url));
const cli = resolve(here, "..", "src", "cli.ts");
const tsxBinName = process.platform === "win32" ? "tsx.cmd" : "tsx";
const tsxBin = resolve(here, "..", "node_modules", ".bin", tsxBinName);

if (!existsSync(tsxBin)) {
  console.error(`✗ tsx not found at ${tsxBin}`);
  console.error(`  Run 'npm install' inside the server/ directory first.`);
  process.exit(1);
}

const child = spawn(tsxBin, [cli, ...process.argv.slice(2)], { stdio: "inherit" });
child.on("exit", (code, signal) => {
  if (signal) process.kill(process.pid, signal);
  else process.exit(code ?? 1);
});
