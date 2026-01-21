#!/usr/bin/env node
import { resolve } from "node:path";
import fs from "node:fs";
import { SyncDaemon } from "./index.js"; // or refactor to export the class
import { config } from "./config.js";
import { log } from "./util/log.js";
import * as ReadLine from "readline";
import { BuildCommand } from "./build.js";
import { PushCommand } from "./push.js";

const args = process.argv.slice(2);
const commandIndex = args.findIndex((a) => !a.startsWith("--"));
const command = commandIndex >= 0 ? args[commandIndex] : null;
const syncDirFlag = args.find((a) => a.startsWith("--sync-dir="));
const portFlag = args.find((a) => a.startsWith("--port="));
const debugFlag = args.find((a) => a === "--debug");
const noWarnFlag = args.find((a) => a === "--no-warn");
const rojoFlag = args.includes("--rojo");
const rojoProjectFlag = getFlagValue(["--rojo-project"], args);

const version = "1.2.1";

if (args.includes("--help") || args.includes("-h")) {
  console.log(`
Usage:
  azul <command> [options]

Commands:
  build                One-time push from filesystem into Studio
  push                 Selective push using mappings (place config or -s/-d)

Global Options:
  -h, --help          Show this help message
  --version           Show Azul version
  --debug             Print verbose debug output
  --no-warn           Disable confirmation prompts for dangerous operations
  --sync-dir=<path>   Directory to sync (default: current directory)
  --port=<number>     Studio connection port

Rojo Compatibility (build & push):
  --rojo              Enable Rojo-compatible parsing
  --rojo-project=FILE Use a Rojo project file (default: default.project.json)

Push Options:
  -s, --source        Source folder to push
  -d, --destination   Destination path (dot or slash separated)
  --no-place-config   Ignore push mappings from place ModuleScript
  --destructive       ⚠ Wipe destination children before pushing
  `);
  process.exit(0);
}

if (args.includes("--version")) {
  log.info(`Azul version: ${version}`);
  process.exit(0);
}

// get current running path
const currentPath = process.cwd();
if (
  (currentPath.includes("\\sync") || currentPath.includes("/sync")) &&
  !noWarnFlag
) {
  log.warn(
    "Looks like you're trying to run Azul from within a 'sync' directory. Continuing to run Azul will create a directory like \"/sync/sync/\".",
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
  if (!rojoFlag && fs.existsSync("default.project.json")) {
    log.warn(
      'Detected default.project.json! You can enable Rojo compatibility mode by passing the "--rojo" flag.',
    );
  }

  if (!noWarnFlag) {
    log.warn(
      "WARNING: Building will overwrite matching Studio scripts and create new ones from your local environment. Existing Studio instances will not be deleted. Proceed with caution!",
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
            "Please answer Y (yes) or N (no). Continue with build? (Y/N)",
          );
        }
      });
    });
  }

  await new BuildCommand({
    syncDir: config.syncDir,
    rojoMode: rojoFlag,
    rojoProjectFile: rojoProjectFlag ?? undefined,
  }).run();

  log.info("Build command completed.");
  log.info("Run 'azul' to resume live sync if needed.");
  log.info("Exiting...");

  process.exit(0);
}

if (command === "push") {
  const sourceValue = getFlagValue(["-s", "--source"], args);
  const destValue = getFlagValue(["-d", "--destination"], args);
  const destructive = args.includes("--destructive");
  const usePlaceConfig = !args.includes("--no-place-config");

  if (!rojoFlag && fs.existsSync("default.project.json")) {
    log.info(
      "Detected default.project.json. Azul stays in native mode unless you pass --rojo.",
    );
  }

  if (destructive && !noWarnFlag) {
    log.warn(
      "WARNING: Destructive push will wipe destination children before applying snapshot. Proceed? (Y/N)",
    );

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
          log.info("Exiting push command...");
          process.exit(0);
        } else {
          log.warn(
            "Please answer Y (yes) or N (no). Continue with destructive push? (Y/N)",
          );
        }
      });
    });
  }

  await new PushCommand({
    source: sourceValue ?? undefined,
    destination: destValue ?? undefined,
    destructive,
    usePlaceConfig: rojoFlag ? false : usePlaceConfig,
    rojoMode: rojoFlag,
    rojoProjectFile: rojoProjectFlag ?? undefined,
  }).run();

  log.info("Push command completed.");
  log.info("Run 'azul' to resume live sync if needed.");
  process.exit(0);
}

new SyncDaemon().start();

function getFlagValue(flags: string[], argv: string[]): string | null {
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    for (const flag of flags) {
      if (arg === flag) {
        return argv[i + 1] ?? null;
      }
      if (arg.startsWith(`${flag}=`)) {
        return arg.split("=")[1] ?? null;
      }
    }
  }
  return null;
}
