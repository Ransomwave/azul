#!/usr/bin/env node
import { resolve } from "node:path";
import { SyncDaemon } from "./index.js"; // or refactor to export the class
import { config } from "./config.js";
import { log } from "./util/log.js";
import * as ReadLine from "readline";

const args = process.argv.slice(2);
const syncDirFlag = args.find((a) => a.startsWith("--sync-dir="));
const portFlag = args.find((a) => a.startsWith("--port="));

if (args.includes("--help") || args.includes("-h")) {
  console.log(`
Usage: azul [options]

Options:
  --sync-dir=<path>   Specify the directory to sync
  --port=<number>     Specify the port number
  -h, --help          Show this help message
  `);
  process.exit(0);
}

// get current running path
const currentPath = process.cwd();
if (currentPath.includes("\\sync") || currentPath.includes("/sync")) {
  log.warn(
    "Looks like you're trying to run Azul from within a 'sync' directory. It's recommended to run Azul from your project root to avoid potential issues."
  );
  log.warn("Continue? (Y/N)");

  await new Promise<void>((resolve) => {
    process.stdin.setEncoding("utf-8");
    const rl = ReadLine.createInterface({
      input: process.stdin,
      output: process.stdout,
    });

    rl.on("line", (input) => {
      const answer = input.trim().toLowerCase();
      if (answer === "y" || answer === "yes") {
        rl.close();
        resolve();
      } else if (answer === "n" || answer === "no") {
        log.info("Exiting. Please run azul from your project root.");
        process.exit(0);
      } else {
        log.warn("Please answer Y (yes) or N (no). Are you sure? (Y/N)");
      }
    });
  });
}

log.info(`Running azul from: ${currentPath}`);

if (syncDirFlag) config.syncDir = resolve(syncDirFlag.split("=")[1]);
if (portFlag) config.port = Number(portFlag.split("=")[1]);

new SyncDaemon().start();
