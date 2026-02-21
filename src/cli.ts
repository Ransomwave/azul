#!/usr/bin/env node
import { resolve, dirname } from "node:path";
import fs from "node:fs";
import { spawn } from "node:child_process";
import { SyncDaemon } from "./index.js"; // or refactor to export the class
import { config, getUserConfigPath, initializeConfig } from "./config.js";
import { log } from "./util/log.js";
import * as ReadLine from "readline";
import { BuildCommand } from "./build.js";
import { PushCommand } from "./push.js";
import { PackCommand } from "./pack.js";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const pkg = JSON.parse(
  fs.readFileSync(resolve(__dirname, "../package.json"), "utf8"),
);
const { version } = pkg;

const args = process.argv.slice(2);
const commandIndex = args.findIndex((a) => !a.startsWith("--"));
const command = commandIndex >= 0 ? args[commandIndex] : null;
const syncDirFlag = args.find((a) => a.startsWith("--sync-dir="));
const portFlag = args.find((a) => a.startsWith("--port="));
const debugFlag = args.find((a) => a === "--debug");
const noWarnFlag = args.find((a) => a === "--no-warn");
const rojoFlag = args.includes("--rojo");
const rojoProjectFlag = getFlagValue(["--rojo-project"], args);
const fromSourcemapValue = getFlagValue(["--from-sourcemap"], args);
const fromSourcemapFlag =
  args.includes("--from-sourcemap") || fromSourcemapValue !== null;

if (args.includes("--help") || args.includes("-h")) {
  console.log(`
Usage:
  azul <command> [options]

Commands:
  (no command)         Start live sync daemon
  build                One-time push from filesystem into Studio
  push                 Selective push using mappings (place config or -s/-d)
  pack                 Serialize Studio instance properties into sourcemap.json
  config               Open the Azul config file in your default editor

Global Options:
  -h, --help          Show this help message
  --version           Show Azul version
  --debug             Print verbose debug output
  --no-warn           Disable confirmation prompts for dangerous operations
  --sync-dir=<path>   Directory to sync (default: current directory)
  --port=<number>     Studio connection port
  --from-sourcemap    Build/push from sourcemap.json (recreate non-script instances)

Rojo Compatibility (for Build & Push):
  --rojo              Enable Rojo-compatible parsing
  --rojo-project=FILE Use a Rojo project file (default: default.project.json)

Push Options:
  -s, --source        Source folder to push
  -d, --destination   Destination path (dot or slash separated)
  --no-place-config   Ignore push mappings from place ModuleScript
  --destructive       ⚠ Wipe destination children before pushing

Pack Options:
  -o, --output        Sourcemap path to write (default: config.sourcemapPath)
  --scripts-only      Serialize only scripts and their descendants

Config Options:
  --path              Print config file path and exit
  `);
  process.exit(0);
}

if (args.includes("--version")) {
  log.info(`Azul version: ${version}`);
  process.exit(0);
}

initializeConfig();
log.debug(`Loaded user config from: ${getUserConfigPath()}`);

if (command === "config") {
  const userConfigPath = getUserConfigPath();

  if (args.includes("--path")) {
    console.log(userConfigPath);
    process.exit(0);
  }

  try {
    await openWithDefaultEditor(userConfigPath);
    log.info(`Opened Azul config: ${userConfigPath}`);
  } catch (error) {
    log.error(`Failed to open config file: ${error}`);
    process.exit(1);
  }

  process.exit(0);
}

// get current running path
const currentPath = process.cwd();
if (
  (currentPath.includes(`\\${config.syncDir}`) ||
    currentPath.includes(`/${config.syncDir}`)) &&
  !noWarnFlag
) {
  log.warn(
    `Looks like you're trying to run Azul from within a '${config.syncDir}' directory. Continuing to run Azul will create a directory like "/${config.syncDir}/${config.syncDir}/".`,
  );
  log.userInput("Continue? (Y/N)");

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
        log.userInput("Please answer Y (yes) or N (no). Are you sure? (Y/N)");
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

  const hasBuildSpecificOptions =
    rojoFlag || Boolean(rojoProjectFlag) || fromSourcemapFlag;
  let applySourcemap = !fromSourcemapFlag;
  let fromSourcemap = fromSourcemapFlag;

  if (!hasBuildSpecificOptions) {
    const sourcemapExists = fs.existsSync(config.sourcemapPath);
    if (sourcemapExists) {
      log.userInput(
        `Build directly from ${config.sourcemapPath} (includes non-script instances)? (Y/N)`,
      );
      const useFull = await promptYesNo();
      if (useFull) {
        fromSourcemap = true;
        applySourcemap = false;
      } else {
        log.userInput(
          `Use packed properties/attributes from ${config.sourcemapPath}? (Y/N)`,
        );
        applySourcemap = await promptYesNo();
      }
    } else {
      applySourcemap = false;
      log.info(
        `No sourcemap found at ${config.sourcemapPath}. Build will recreate instances as scripts/folders.`,
      );
    }
  }

  if (!noWarnFlag) {
    log.warn(
      "WARNING: Building will overwrite matching Studio scripts and create new ones from your local environment. Existing Studio instances will not be deleted. Proceed with caution!",
    );
    log.userInput("Continue with build? (Y/N)");

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
          log.userInput(
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
    applySourcemap,
    fromSourcemap,
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

  const hasPushSpecificOptions = Boolean(
    sourceValue ||
    destValue ||
    destructive ||
    !usePlaceConfig ||
    rojoFlag ||
    rojoProjectFlag ||
    fromSourcemapFlag,
  );

  let interactiveSource = sourceValue ?? undefined;
  let interactiveDest = destValue ?? undefined;
  let interactiveDestructive = destructive;
  let interactiveUsePlaceConfig = usePlaceConfig;
  let applySourcemap = !rojoFlag && !fromSourcemapFlag;
  let fromSourcemap = !rojoFlag && fromSourcemapFlag;

  if (!hasPushSpecificOptions && !rojoFlag) {
    log.userInput(
      "Use place config from Studio (ServerStorage.Azul.Config)? (Y/N)",
    );
    const useConfig = await promptYesNo();
    interactiveUsePlaceConfig = useConfig;

    if (!useConfig) {
      log.userInput("Source folder to push (e.g., src)?");
      interactiveSource = (await promptLine()).trim() || undefined;
      log.userInput(
        "Destination path (dot or slash separated, e.g., ReplicatedStorage.Packages)?",
      );
      interactiveDest = (await promptLine()).trim() || undefined;
      log.userInput("Destructive push (wipe destination children)? (Y/N)");
      interactiveDestructive = await promptYesNo();
    }

    if (fs.existsSync(config.sourcemapPath)) {
      log.userInput(
        `Build push snapshot directly from ${config.sourcemapPath} (includes non-script descendants)? (Y/N)`,
      );
      fromSourcemap = await promptYesNo();
      if (!fromSourcemap) {
        log.userInput(
          `Apply packed properties/attributes from ${config.sourcemapPath}? (Y/N)`,
        );
        applySourcemap = await promptYesNo();
      }
    } else {
      fromSourcemap = false;
      applySourcemap = false;
      log.info(
        `No sourcemap found at ${config.sourcemapPath}. Push will recreate instances as scripts/folders.`,
      );
    }
  }

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
          log.userInput(
            "Please answer Y (yes) or N (no). Continue with destructive push? (Y/N)",
          );
        }
      });
    });
  }

  await new PushCommand({
    source: interactiveSource ?? undefined,
    destination: interactiveDest ?? undefined,
    destructive: interactiveDestructive,
    usePlaceConfig: rojoFlag ? false : interactiveUsePlaceConfig,
    rojoMode: rojoFlag,
    rojoProjectFile: rojoProjectFlag ?? undefined,
    applySourcemap,
    fromSourcemap,
    sourcemapPath:
      fromSourcemapValue && !fromSourcemapValue.startsWith("--")
        ? fromSourcemapValue
        : undefined,
  }).run();

  log.info("Push command completed.");
  log.info("Run 'azul' to resume live sync if needed.");
  process.exit(0);
}

if (command === "pack") {
  const outputValue = getFlagValue(["-o", "--output"], args);
  let scriptsOnly = args.includes("--scripts-only");

  const hasPackSpecificOptions =
    outputValue !== null || args.includes("--scripts-only");

  let finalOutputPath = outputValue ?? config.sourcemapPath;

  if (!hasPackSpecificOptions) {
    const interactive = await promptPackInteractive(config.sourcemapPath);
    finalOutputPath = interactive.outputPath;
    scriptsOnly = interactive.scriptsOnly;
  }

  await new PackCommand({
    outputPath: finalOutputPath,
    scriptsAndDescendantsOnly: scriptsOnly,
  }).run();

  log.info("Pack command completed.");
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

function openWithDefaultEditor(targetPath: string): Promise<void> {
  return new Promise((resolvePromise, rejectPromise) => {
    const currentPlatform = process.platform;

    const argsByPlatform: Record<string, string[]> = {
      win32: ["/c", "start", "", targetPath],
      darwin: [targetPath],
      linux: [targetPath],
    };

    const commandByPlatform: Record<string, string> = {
      win32: "cmd",
      darwin: "open",
      linux: "xdg-open",
    };

    const commandName = commandByPlatform[currentPlatform];
    const commandArgs = argsByPlatform[currentPlatform];

    if (!commandName || !commandArgs) {
      rejectPromise(new Error(`Unsupported platform: ${currentPlatform}`));
      return;
    }

    const child = spawn(commandName, commandArgs, {
      detached: true,
      stdio: "ignore",
    });

    child.on("error", (error: NodeJS.ErrnoException) => {
      if (currentPlatform === "linux" && error.code === "ENOENT") {
        rejectPromise(
          new Error(
            "Could not open config file because 'xdg-open' is not installed. Install it (i.e: 'sudo apt install xdg-utils' or 'sudo dnf install xdg-utils') and try again.",
          ),
        );
        return;
      }

      rejectPromise(error);
    });

    child.unref();
    resolvePromise();
  });
}

async function promptPackInteractive(defaultOutputPath: string): Promise<{
  outputPath: string;
  scriptsOnly: boolean;
}> {
  log.info("Interactive mode: configuring 'azul pack'.");
  log.userInput("Serialize everything? (Y/N)");
  const scriptsOnly = !(await promptYesNo());

  if (scriptsOnly) {
    log.info(
      "Scripts-only mode will only serialize Script, LocalScript, and ModuleScript instances and their descendants.",
    );
  }

  log.userInput(
    `Output sourcemap path? (press Enter for '${defaultOutputPath}')`,
  );
  const outputInput = await promptLine();
  const outputPath =
    outputInput.trim() === "" ? defaultOutputPath : outputInput.trim();

  return {
    outputPath,
    scriptsOnly,
  };
}

function promptLine(): Promise<string> {
  return new Promise((resolve) => {
    const rl = ReadLine.createInterface({
      input: process.stdin,
      output: process.stdout,
    });

    rl.once("line", (input) => {
      rl.close();
      resolve(input);
    });
  });
}

async function promptYesNo(): Promise<boolean> {
  while (true) {
    const input = (await promptLine()).trim().toLowerCase();
    if (input === "y" || input === "yes") {
      return true;
    }
    if (input === "n" || input === "no") {
      return false;
    }
    log.userInput("Please answer Y (yes) or N (no).");
  }
}
