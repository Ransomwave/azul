#!/usr/bin/env node
import { resolve } from "node:path";
import { SyncDaemon } from "./index.js"; // or refactor to export the class
import { config } from "./config.js";
import { log } from "./util/log.js";
import * as ReadLine from "readline";
import { BuildCommand } from "./build.js";

const args = process.argv.slice(2);
const commandIndex = args.findIndex((a) => !a.startsWith("--"));
const command = commandIndex >= 0 ? args[commandIndex] : null;
const syncDirFlag = args.find((a) => a.startsWith("--sync-dir="));
const portFlag = args.find((a) => a.startsWith("--port="));
const debugFlag = args.find((a) => a === "--debug");
const noWarnFlag = args.find((a) => a === "--no-warn");

const version = "1.0.1";

if (args.includes("--help") || args.includes("-h")) {
  console.log(`
Usage: azul [command] [options]

Arguments:
  [arg]               Optional argument or command
  <arg>               Required argument or command 

Commands:
  build                One-time push from filesystem into Studio

Options:
  --version           Show Azul version
  --no-warn           Disable warning prompts for dangerous operations (like running in /sync or using build)
  --sync-dir=<path>   Specify the directory to sync
  --port=<number>     Specify the port number
  --debug             Enables debug mode
  -h, --help          Show this help message
  `);
  process.exit(0);
}

if (args.includes("--version")) {
  console.log(`Azul version: ${version}`);
  process.exit(0);
}

// get current running path
const currentPath = process.cwd();
if (
  (currentPath.includes("\\sync") || currentPath.includes("/sync")) &&
  !noWarnFlag
) {
  log.warn(
    "Looks like you're trying to run Azul from within a 'sync' directory. Continuing to run Azul will create a directory like \"/sync/sync/\"."
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
if (debugFlag) config.debugMode = true;

log.debug(`Debug mode is on!`);

if (command === "build") {
  if (!noWarnFlag) {
    log.warn(
      "WARNING: Building will overwrite matching Studio scripts and create new ones from your local environment. Existing Studio instances will not be deleted. Proceed with caution!"
    );
    log.info("Continue with build? (Y/N)");

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
          log.info("Exiting build command...");
          process.exit(0);
        } else {
          log.warn(
            "Please answer Y (yes) or N (no). Continue with build? (Y/N)"
          );
        }
      });
    });
  }

  await new BuildCommand({ syncDir: config.syncDir }).run();

  log.info("Build command completed.");
  log.info(
    "To continue syncing, please run 'azul' and restart the Roblox plugin."
  );
  log.info("Exiting...");

  process.exit(0);
}

new SyncDaemon().start();
